import CoreAudio
import Foundation
import MixpilotCore
import os

/// What Mixpilot wants for one app, as the UI knows it.
public struct TapRequest: Sendable, Equatable {
    public var appID: String
    public var processObjectIDs: [UInt32]
    /// The person's volume and mute.
    public var gain: Double
    /// Call mode's level: 1 = not lowered.
    public var duck: Double
    public var isPlaying: Bool
    /// The devices the app plays to; empty if it isn't playing.
    public var outputDeviceIDs: [UInt32]
    /// The device the person chose for the app (UID). Used while it is connected; otherwise the
    /// app plays where it would on its own.
    public var preferredOutputUID: String?

    public init(
        appID: String,
        processObjectIDs: [UInt32],
        gain: Double,
        duck: Double = 1,
        isPlaying: Bool,
        outputDeviceIDs: [UInt32],
        preferredOutputUID: String? = nil
    ) {
        self.appID = appID
        self.processObjectIDs = processObjectIDs
        self.gain = gain
        self.duck = duck
        self.isPlaying = isPlaying
        self.outputDeviceIDs = outputDeviceIDs
        self.preferredOutputUID = preferredOutputUID
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
    /// Apps whose session is about to be rebuilt (coalesces bursts of device notifications).
    private var pendingRebuilds: Set<String> = []
    /// Recent rebuild times per app, to give up on an app that keeps failing.
    private var rebuildTimes: [String: [Double]] = [:]
    /// When each app's last session was released. A new tap for the same app is created only after
    /// `recreateDelay`: creating one right after destroying the previous one blocks and fails.
    private var releasedAt: [String: Double] = [:]
    private var cooldownWork: DispatchWorkItem?
    /// Render callback counts at the last watchdog check, per running session.
    private var lastCallbackCounts: [String: UInt64] = [:]
    private var watchdog: DispatchSourceTimer?

    /// After a failure, wait this long before trying the same app again.
    private static let failureBackoff: Double = 10
    /// More rebuilds than this within `rebuildWindow` seconds count as a failure.
    private static let maxRebuilds = 3
    private static let rebuildWindow: Double = 10
    private static let recreateDelay: Double = 1.5
    private static let stallReason = "audio stalled"
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
            watchdog?.cancel()
            watchdog = nil
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
        let available = Set(DeviceMonitor.current().outputs.map(\.id))
        let targets = requests.map { request in
            let own = outputUID(for: request, default: defaultUID)
            // The chosen device wins while it is connected.
            let chosen = request.preferredOutputUID.flatMap { available.contains($0) ? $0 : nil }
            return TapTarget(
                appID: request.appID,
                processObjectIDs: request.processObjectIDs,
                gain: request.gain,
                duck: request.duck,
                isPlaying: request.isPlaying,
                outputDeviceUID: chosen ?? own,
                isRerouted: chosen.map { $0 != own } ?? false
            )
        }
        failedUntil = failedUntil.filter { $0.value > now }
        releasedAt = releasedAt.filter { now - $0.value < Self.recreateDelay }
        let blocked = isPermissionDenied
            ? Set(targets.map(\.appID))
            : Set(failedUntil.keys).union(releasedAt.keys)
        let states = sessions.mapValues {
            TapSessionState(
                processObjectIDs: $0.processObjectIDs,
                outputDeviceUID: $0.outputDeviceUID,
                gain: $0.gain,
                duck: $0.duck,
                isRunning: $0.isRunning,
                unitySince: $0.unitySince
            )
        }

        for action in TapPlanner.plan(targets: targets, sessions: states, now: now, blocked: blocked) {
            apply(action, now: now)
        }
        scheduleDeadline()
        scheduleCooldownEnd()
        updateWatchdog()
    }

    /// Plans again when the earliest re-create delay ends, so a waiting app gets its session.
    private func scheduleCooldownEnd() {
        cooldownWork?.cancel()
        guard let earliest = releasedAt.values.min() else { return }
        let work = DispatchWorkItem { [weak self] in self?.reconcile() }
        cooldownWork = work
        let delay = max(0, earliest + Self.recreateDelay - ProcessInfo.processInfo.systemUptime) + 0.05
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Destroys an app's session and remembers when, for the re-create delay.
    private func release(_ appID: String) {
        guard let session = sessions.removeValue(forKey: appID) else { return }
        session.destroy()
        lastCallbackCounts[appID] = nil
        releasedAt[appID] = ProcessInfo.processInfo.systemUptime
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
                watchHealth(of: session)
                if target.isPlaying {
                    try start(session)
                }
                // Starts at 1 and fades down, so call mode lowers newly playing apps calmly too.
                session.setDuck(target.duck)
                let milliseconds = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                log.info("Tapping \(target.appID, privacy: .public) on \(target.outputDeviceUID, privacy: .public) (\(milliseconds) ms)")
            } catch {
                fail(target.appID, error, now: now)
            }
        case .destroy(let appID):
            release(appID)
            log.info("Released \(appID, privacy: .public)")
        case .setOutput(let appID, let deviceUID):
            do {
                try sessions[appID]?.switchOutput(to: deviceUID)
                log.info("Moved \(appID, privacy: .public) to \(deviceUID, privacy: .public)")
            } catch {
                fail(appID, error, now: now)
            }
        case .setGain(let appID, let gain):
            guard let session = sessions[appID] else { return }
            session.setGain(gain)
            updateUnity(of: session, now: now)
        case .setDuck(let appID, let duck):
            guard let session = sessions[appID] else { return }
            session.setDuck(duck)
            updateUnity(of: session, now: now)
            log.info("\(appID, privacy: .public) \(duck < 1 ? "lowered for call mode" : "back from call mode", privacy: .public)")
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
            lastCallbackCounts[appID] = nil
            log.info("Paused \(appID, privacy: .public)")
        }
    }

    /// Records when a session got back to gain 1 and duck 1, for the grace period.
    private func updateUnity(of session: TapSession, now: Double) {
        session.unitySince = session.gain == 1 && session.duck == 1 ? (session.unitySince ?? now) : nil
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
            if AudioPermission.isGranted() {
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

    // MARK: Health

    private func watchHealth(of session: TapSession) {
        let appID = session.appID
        let identity = ObjectIdentifier(session)
        session.watchHealth(queue: queue) { [weak self] in
            guard let self, let current = self.sessions[appID], ObjectIdentifier(current) == identity,
                  current.isBroken
            else { return }
            self.scheduleRebuild(appID, reason: "output device went away")
        }
    }

    /// Rebuilds a session's output shortly (device changes come in bursts), keeping its tap. The
    /// new output uses the device's and the tap's current formats.
    private func scheduleRebuild(_ appID: String, reason: String) {
        guard !pendingRebuilds.contains(appID) else { return }
        pendingRebuilds.insert(appID)
        queue.asyncAfter(deadline: .now() + 0.25) { [self] in
            pendingRebuilds.remove(appID)
            guard let session = sessions[appID] else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let recent = (rebuildTimes[appID] ?? []).filter { now - $0 < Self.rebuildWindow } + [now]
            rebuildTimes[appID] = recent
            guard recent.count <= Self.maxRebuilds else {
                // Keeps breaking: let the app play on its own for a while.
                fail(appID, CoreAudioError(operation: "Too many rebuilds", status: kAudioHardwareUnspecifiedError), now: now)
                reconcile()
                return
            }
            log.notice("Rebuilding \(appID, privacy: .public): \(reason, privacy: .public)")
            lastCallbackCounts[appID] = nil
            // The device may be gone for good: plan with the devices there are now, which moves
            // the output elsewhere if needed. Rebuild in place only if that didn't fix it.
            reconcile()
            guard let current = sessions[appID], current === session, session.isBroken || reason == Self.stallReason else {
                return
            }
            do {
                try session.switchOutput(to: session.outputDeviceUID)
            } catch {
                fail(appID, error, now: now)
            }
        }
    }

    /// While audio runs, checks every 2 s that each running session still renders. A stalled
    /// session (its device stopped without a notification) is rebuilt.
    private func updateWatchdog() {
        let anyRunning = sessions.values.contains(where: \.isRunning)
        if anyRunning, watchdog == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.checkStalls() }
            timer.resume()
            watchdog = timer
        } else if !anyRunning, let timer = watchdog {
            timer.cancel()
            watchdog = nil
            lastCallbackCounts = [:]
        }
    }

    private func checkStalls() {
        for (appID, session) in sessions where session.isRunning {
            let count = session.callbackCount
            if let last = lastCallbackCounts[appID], last == count {
                scheduleRebuild(appID, reason: Self.stallReason)
            }
            lastCallbackCounts[appID] = count
        }
    }

    private func fail(_ appID: String, _ error: Error, now: Double) {
        log.error("\(appID, privacy: .public): \(String(describing: error), privacy: .public)")
        release(appID)
        failedUntil[appID] = now + Self.failureBackoff
    }

    private func destroyAll() {
        for appID in Array(sessions.keys) {
            release(appID)
        }
    }

    /// Re-plans when a session's grace period at 100 % ends.
    private func scheduleDeadline() {
        deadline?.cancel()
        let states = sessions.mapValues {
            TapSessionState(processObjectIDs: [], outputDeviceUID: "", gain: $0.gain, duck: $0.duck, isRunning: false, unitySince: $0.unitySince)
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
