import CoreAudio
import Foundation
import MixpilotCore
import os

/// What Mixpilot wants for one app, as the UI knows it.
public struct TapRequest: Sendable, Equatable {
    public var appID: String
    public var processObjectIDs: [UInt32]
    public var gain: Double
    public var isPlaying: Bool
    /// The devices the app plays to; empty if it isn't playing.
    public var outputDeviceIDs: [UInt32]

    public init(appID: String, processObjectIDs: [UInt32], gain: Double, isPlaying: Bool, outputDeviceIDs: [UInt32]) {
        self.appID = appID
        self.processObjectIDs = processObjectIDs
        self.gain = gain
        self.isPlaying = isPlaying
        self.outputDeviceIDs = outputDeviceIDs
    }
}

public enum TapEvent: Sendable, Equatable {
    /// Mixpilot can't hear apps: the System Audio Recording permission is missing.
    case permissionDenied
    /// The permission is there (again).
    case permissionGranted
}

/// Keeps one `TapSession` per app whose volume differs from 100 %, matching what the UI asks for.
///
/// Requests arrive from the main actor; sessions are created, changed and destroyed on the
/// manager's own queue (Core Audio calls can block). Decisions come from `TapPlanner`.
public final class TapManager: @unchecked Sendable {
    public let events: AsyncStream<TapEvent>

    private let continuation: AsyncStream<TapEvent>.Continuation
    private let queue = DispatchQueue(label: "app.mixpilot.taps", qos: .userInitiated)
    private let log = Logger.mixpilot("taps")

    // Confined to `queue`.
    private var sessions: [String: TapSession] = [:]
    private var requests: [TapRequest] = []
    /// Apps whose session failed recently, with the time until which none is created.
    private var failedUntil: [String: Double] = [:]
    private var isPermissionDenied = false
    private var deadline: DispatchWorkItem?
    private var permissionRetry: DispatchWorkItem?

    /// After a failure, wait this long before trying the same app again.
    private static let failureBackoff: Double = 10
    /// How long a started session may deliver only silence before the permission is checked.
    private static let signalTimeout: Double = 2

    public init() {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(4))
    }

    /// Replaces what Mixpilot should do for every app Core Audio knows about.
    public func update(_ requests: [TapRequest]) {
        queue.async { [self] in
            self.requests = requests
            reconcile()
        }
    }

    /// Destroys every session so all apps are heard on their own. Blocks until done: call it before
    /// quitting.
    public func stopAll() {
        queue.sync {
            deadline?.cancel()
            permissionRetry?.cancel()
            for session in sessions.values {
                session.destroy()
            }
            if !sessions.isEmpty {
                log.notice("Stopped \(self.sessions.count) sessions")
            }
            sessions = [:]
            requests = []
        }
    }

    /// Removes taps and aggregate devices an earlier Mixpilot left behind. Private ones disappear
    /// with their process, so this only finds objects from older builds or unusual exits.
    @discardableResult
    public static func removeLeftovers() -> Int {
        var removed = 0
        for device in AudioDevices.all() {
            if let uid = AudioDevices.uid(of: device), uid.hasPrefix(TapSession.aggregateUIDPrefix),
               AudioHardwareDestroyAggregateDevice(device) == noErr {
                removed += 1
            }
        }
        for tap in HAL.objectIDs(HAL.systemObject, kAudioHardwarePropertyTapList) {
            if let name = tapName(tap), name.hasPrefix(TapSession.tapNamePrefix),
               AudioHardwareDestroyProcessTap(tap) == noErr {
                removed += 1
            }
        }
        if removed > 0 {
            Logger.mixpilot("taps").notice("Removed \(removed) leftover audio objects")
        }
        return removed
    }

    // MARK: - On the queue

    private func reconcile() {
        let now = ProcessInfo.processInfo.systemUptime
        guard let defaultUID = AudioDevices.defaultOutput().flatMap(AudioDevices.uid(of:)) else {
            // No output device at all: nothing can be played, so hold nothing.
            destroyAll()
            return
        }
        let targets = requests.map { request in
            TapTarget(
                appID: request.appID,
                processObjectIDs: request.processObjectIDs,
                gain: request.gain,
                isPlaying: request.isPlaying,
                outputDeviceUID: outputUID(for: request, default: defaultUID)
            )
        }
        failedUntil = failedUntil.filter { $0.value > now }
        let blocked = isPermissionDenied ? Set(targets.map(\.appID)) : Set(failedUntil.keys)
        let states = sessions.mapValues {
            TapSessionState(
                processObjectIDs: $0.processObjectIDs,
                outputDeviceUID: $0.outputDeviceUID,
                gain: $0.gain,
                isRunning: $0.isRunning,
                unitySince: $0.unitySince
            )
        }

        for action in TapPlanner.plan(targets: targets, sessions: states, now: now, blocked: blocked) {
            apply(action, now: now)
        }
        scheduleDeadline()
    }

    private func apply(_ action: TapAction, now: Double) {
        switch action {
        case .create(let target):
            do {
                let started = ProcessInfo.processInfo.systemUptime
                let session = try TapSession(
                    appID: target.appID,
                    processObjectIDs: target.processObjectIDs,
                    gain: target.gain,
                    outputDeviceUID: target.outputDeviceUID
                )
                sessions[target.appID] = session
                if target.isPlaying {
                    try start(session)
                }
                let milliseconds = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                log.info("Tapping \(target.appID, privacy: .public) on \(target.outputDeviceUID, privacy: .public) (\(milliseconds) ms)")
            } catch {
                fail(target.appID, error, now: now)
            }
        case .destroy(let appID):
            sessions.removeValue(forKey: appID)?.destroy()
            log.info("Released \(appID, privacy: .public)")
        case .setGain(let appID, let gain):
            guard let session = sessions[appID] else { return }
            session.setGain(gain)
            session.unitySince = gain == 1 ? (session.unitySince ?? now) : nil
        case .setProcesses(let appID, let processObjectIDs):
            do {
                try sessions[appID]?.setProcesses(processObjectIDs)
            } catch {
                fail(appID, error, now: now)
            }
        case .start(let appID):
            guard let session = sessions[appID] else { return }
            do {
                try start(session)
                log.info("Resumed \(appID, privacy: .public)")
            } catch {
                fail(appID, error, now: now)
            }
        case .stop(let appID):
            sessions[appID]?.stop()
            log.info("Paused \(appID, privacy: .public)")
        }
    }

    private func start(_ session: TapSession) throws {
        try session.start()
        // A tap without permission delivers only silence while still muting the app (or the
        // permission prompt is still open). Check once audio should have arrived.
        let appID = session.appID
        let identity = ObjectIdentifier(session)
        queue.asyncAfter(deadline: .now() + Self.signalTimeout) { [weak self] in
            // Only if the same session still exists.
            guard let self, let current = self.sessions[appID], ObjectIdentifier(current) == identity else { return }
            self.checkSignal(of: current)
        }
    }

    private func checkSignal(of session: TapSession) {
        guard session.isRunning else { return }
        guard !session.hasReceivedSignal else {
            log.info("\(session.appID, privacy: .public): audio is flowing")
            return
        }
        let status = session.writeDescription()
        guard status == kAudioDevicePermissionsError else {
            // Permission is fine; the app is just quiet (paused with its stream open).
            return
        }
        log.notice("No permission to capture audio; releasing all apps")
        isPermissionDenied = true
        destroyAll()
        continuation.yield(.permissionDenied)
        schedulePermissionRetry()
    }

    /// While the permission is missing, check every few seconds whether it was granted (in the
    /// system prompt or in System Settings), then pick up where the user left off.
    private func schedulePermissionRetry() {
        permissionRetry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isPermissionDenied else { return }
            if Self.hasPermission() {
                self.log.notice("Audio capture permission granted")
                self.isPermissionDenied = false
                self.continuation.yield(.permissionGranted)
                self.reconcile()
            } else {
                self.schedulePermissionRetry()
            }
        }
        permissionRetry = work
        queue.asyncAfter(deadline: .now() + 3, execute: work)
    }

    /// Probes the permission with a tap that mutes nothing and is never read.
    private static func hasPermission() -> Bool {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.isPrivate = true
        description.muteBehavior = .unmuted
        description.name = TapSession.tapNamePrefix + "permission check"
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { return false }
        defer { AudioHardwareDestroyProcessTap(tap) }
        var address = HAL.address(kAudioTapPropertyDescription)
        var reference = Unmanaged.passUnretained(description)
        let status = AudioObjectSetPropertyData(
            tap, &address, 0, nil, UInt32(MemoryLayout<Unmanaged<CATapDescription>>.size), &reference
        )
        return status != kAudioDevicePermissionsError
    }

    private func fail(_ appID: String, _ error: Error, now: Double) {
        log.error("\(appID, privacy: .public): \(String(describing: error), privacy: .public)")
        sessions.removeValue(forKey: appID)?.destroy()
        failedUntil[appID] = now + Self.failureBackoff
    }

    private func destroyAll() {
        for session in sessions.values {
            session.destroy()
        }
        sessions = [:]
    }

    /// Re-plans when a session's grace period at 100 % ends.
    private func scheduleDeadline() {
        deadline?.cancel()
        let states = sessions.mapValues {
            TapSessionState(processObjectIDs: [], outputDeviceUID: "", gain: $0.gain, isRunning: false, unitySince: $0.unitySince)
        }
        guard let time = TapPlanner.nextDeadline(sessions: states) else { return }
        let work = DispatchWorkItem { [weak self] in self?.reconcile() }
        deadline = work
        let delay = max(0, time - ProcessInfo.processInfo.systemUptime) + 0.05
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// The device the app plays to, or the system default if it isn't playing anywhere.
    private func outputUID(for request: TapRequest, default defaultUID: String) -> String {
        for device in request.outputDeviceIDs {
            if let uid = AudioDevices.uid(of: device), !uid.hasPrefix(TapSession.aggregateUIDPrefix) {
                return uid
            }
        }
        return defaultUID
    }

    private static func tapName(_ tap: AudioObjectID) -> String? {
        var address = HAL.address(kAudioTapPropertyDescription)
        var size = UInt32(MemoryLayout<Unmanaged<CATapDescription>?>.size)
        var description: Unmanaged<CATapDescription>?
        let status = withUnsafeMutablePointer(to: &description) {
            AudioObjectGetPropertyData(tap, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return description?.takeRetainedValue().name
    }
}
