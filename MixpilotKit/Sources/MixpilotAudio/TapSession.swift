import CoreAudio
import Foundation
import MixpilotRender
import os

/// One app's sound, routed through Mixpilot so its volume and output device can change.
///
/// - A private process tap captures the app's processes and mutes their own output only while
///   Mixpilot reads the tap (`.mutedWhenTapped`). If Mixpilot stops reading (the session stops, the
///   app quits, Mixpilot crashes), the app is heard on its own again: a failure never means silence.
///   The tap lives as long as the session: destroying a tap and creating another for the same app
///   right away blocks for over a second and fails (macOS 27).
/// - An `Output` plays the tap on one device: a private aggregate device (tap as input, the device
///   as output) with the C IOProc `MPRenderIOProc` applying the gain. Switching devices or
///   recovering from a device change replaces only the output, make-before-break.
///
/// Not thread-safe: `TapManager` uses sessions from its queue only.
final class TapSession {
    /// Names Mixpilot's taps and prefixes its aggregate device UIDs, to find leftovers.
    static let tapNamePrefix = "Mixpilot "
    static let aggregateUIDPrefix = "app.mixpilot.tap."

    let appID: String
    private(set) var processObjectIDs: [AudioObjectID]
    private(set) var gain: Double
    /// Call mode's level (1 = not lowered). Starts at 1 so a new session fades down to it.
    private(set) var duck: Double = 1
    /// Since when gain and duck have been back at 1 (see `TapPlanner.unityGrace`).
    var unitySince: Double?

    private let tapDescription: CATapDescription
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var output: Output?
    private var tapListener: HALListener?
    private var health: (queue: DispatchQueue, onProblem: () -> Void)?

    init(appID: String, processObjectIDs: [AudioObjectID], gain: Double, outputDeviceUID: String) throws {
        self.appID = appID
        self.processObjectIDs = processObjectIDs
        self.gain = gain

        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.uuid = UUID()
        description.name = Self.tapNamePrefix + appID
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        tapDescription = description

        do {
            try check(AudioHardwareCreateProcessTap(description, &tapID), "Create tap")
            guard tapID != kAudioObjectUnknown else {
                // Seen when a tap on the same app was destroyed moments before.
                throw CoreAudioError(operation: "Create tap (no object)", status: kAudioHardwareBadObjectError)
            }
            output = try makeOutput(on: outputDeviceUID)
        } catch {
            destroy()
            throw error
        }
    }

    var outputDeviceUID: String {
        output?.deviceUID ?? ""
    }

    var isRunning: Bool {
        output?.isRunning ?? false
    }

    /// Starts audio: from now on the app is heard through Mixpilot.
    func start() throws {
        try output?.start()
    }

    /// Stops audio: the app is heard on its own again (it isn't playing anyway when this is called).
    func stop() {
        output?.stop()
    }

    func setGain(_ gain: Double) {
        self.gain = gain
        output?.setGain(gain)
    }

    /// Fades to call mode's level for this app.
    func setDuck(_ duck: Double) {
        self.duck = duck
        output?.setDuck(duck)
    }

    /// Changes which processes are tapped (an app started or stopped a helper), without a gap.
    func setProcesses(_ processObjectIDs: [AudioObjectID]) throws {
        tapDescription.processes = processObjectIDs
        try check(writeDescription(), "Update tap processes")
        self.processObjectIDs = processObjectIDs
    }

    /// Plays the app on another device (or rebuilds the output on the same one after a device or
    /// format change). The new output starts before the old one stops, so the app is never heard
    /// on its own in between.
    func switchOutput(to deviceUID: String) throws {
        let replacement = try makeOutput(on: deviceUID)
        if isRunning {
            do {
                try replacement.start()
            } catch {
                replacement.destroy()
                throw error
            }
        }
        output?.destroy()
        output = replacement
        if let health {
            watchHealth(queue: health.queue, onProblem: health.onProblem)
        }
    }

    /// How many buffers the audio thread has rendered: if it stops growing while running, IO stalled.
    var callbackCount: UInt64 {
        output?.callbackCount ?? 0
    }

    /// Whether audio has ever come through. A tap without the System Audio Recording permission
    /// only delivers silence.
    var hasReceivedSignal: Bool {
        output?.hasReceivedSignal ?? false
    }

    /// The output's device or aggregate device is gone or dead: the output must be rebuilt.
    /// (Sample rate and format changes alone are fine: the render kernel takes any buffer layout,
    /// and the watchdog catches IO that stops.)
    var isBroken: Bool {
        output?.isBroken ?? true
    }

    /// Calls `onChange` (on `queue`) when something about the output's devices or the tap's format
    /// changed. Check `isBroken` before acting: devices send several notifications while settling.
    func watchHealth(queue: DispatchQueue, onProblem: @escaping () -> Void) {
        health = (queue, onProblem)
        tapListener = HALListener(object: tapID, selector: kAudioTapPropertyFormat, queue: queue, handler: onProblem)
        output?.watchHealth(queue: queue, onProblem: onProblem)
    }

    /// Rewrites the tap's description; returns `kAudioDevicePermissionsError` when the System Audio
    /// Recording permission is missing.
    func writeDescription() -> OSStatus {
        var address = HAL.address(kAudioTapPropertyDescription)
        var reference = Unmanaged.passUnretained(tapDescription)
        return AudioObjectSetPropertyData(
            tapID, &address, 0, nil, UInt32(MemoryLayout<Unmanaged<CATapDescription>>.size), &reference
        )
    }

    /// Tears everything down: output first, then the tap. Safe to call more than once.
    func destroy() {
        tapListener?.remove()
        tapListener = nil
        health = nil
        output?.destroy()
        output = nil
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit {
        destroy()
    }

    private func makeOutput(on deviceUID: String) throws -> Output {
        let format = try Self.readFormat(of: tapID)
        return try Output(
            tapUUID: tapDescription.uuid.uuidString, deviceUID: deviceUID, gain: gain, duck: duck, sampleRate: format.mSampleRate
        )
    }

    /// The tap's stream format, which must be 32-bit float. Waits briefly for a new tap to report it.
    private static func readFormat(of tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var status: OSStatus = noErr
        for _ in 0..<50 {
            var address = HAL.address(kAudioTapPropertyFormat)
            var format = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format)
            if status == noErr, format.mSampleRate > 0, format.mFormatID == kAudioFormatLinearPCM {
                guard format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
                    throw CoreAudioError(operation: "Tap format is not 32-bit float", status: kAudioHardwareUnsupportedOperationError)
                }
                return format
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw CoreAudioError(operation: "Read tap format", status: status == noErr ? kAudioHardwareNotRunningError : status)
    }
}

/// Plays a tap on one device: a private aggregate device (tap in, device out), the C IOProc and
/// its render state.
private final class Output {
    let deviceUID: String
    private(set) var isRunning = false

    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var renderState: OpaquePointer?
    private var listeners: [HALListener] = []

    init(tapUUID: String, deviceUID: String, gain: Double, duck: Double, sampleRate: Double) throws {
        self.deviceUID = deviceUID
        do {
            guard let state = MPRenderStateCreate(Float(gain), Float(duck), sampleRate) else {
                throw CoreAudioError(operation: "Allocate render state", status: kAudio_MemFullError)
            }
            renderState = state

            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Mixpilot",
                kAudioAggregateDeviceUIDKey: TapSession.aggregateUIDPrefix + UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: false,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: tapUUID,
                    kAudioSubTapDriftCompensationKey: true,
                ]],
            ]
            try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregateID), "Create aggregate device")
            try waitUntilReady()
            try check(
                AudioDeviceCreateIOProcID(aggregateID, MPRenderIOProc, UnsafeMutableRawPointer(state), &ioProcID),
                "Create IOProc"
            )
        } catch {
            destroy()
            throw error
        }
    }

    func start() throws {
        guard !isRunning, let ioProcID else { return }
        try check(AudioDeviceStart(aggregateID, ioProcID), "Start")
        isRunning = true
    }

    func stop() {
        guard isRunning, let ioProcID else { return }
        AudioDeviceStop(aggregateID, ioProcID)
        isRunning = false
    }

    func setGain(_ gain: Double) {
        if let renderState {
            MPRenderSetGain(renderState, Float(gain))
        }
    }

    func setDuck(_ duck: Double) {
        if let renderState {
            MPRenderSetDuck(renderState, Float(duck))
        }
    }

    var callbackCount: UInt64 {
        renderState.map(MPRenderCallbackCount) ?? 0
    }

    var hasReceivedSignal: Bool {
        renderState.map(MPRenderHasReceivedSignal) ?? false
    }

    var isBroken: Bool {
        if HAL.flag(aggregateID, kAudioDevicePropertyDeviceIsAlive) == false { return true }
        guard let device = AudioDevices.device(forUID: deviceUID) else { return true }
        return HAL.flag(device, kAudioDevicePropertyDeviceIsAlive) == false
    }

    func watchHealth(queue: DispatchQueue, onProblem: @escaping () -> Void) {
        listeners.forEach { $0.remove() }
        var watched: [(AudioObjectID, AudioObjectPropertySelector)] = [
            (aggregateID, kAudioDevicePropertyDeviceIsAlive),
            (aggregateID, kAudioDevicePropertyNominalSampleRate),
        ]
        if let device = AudioDevices.device(forUID: deviceUID) {
            watched.append((device, kAudioDevicePropertyDeviceIsAlive))
            watched.append((device, kAudioDevicePropertyNominalSampleRate))
        }
        listeners = watched.compactMap { object, selector in
            HALListener(object: object, selector: selector, queue: queue, handler: onProblem)
        }
    }

    /// Tears down in reverse order. Safe to call more than once.
    func destroy() {
        listeners.forEach { $0.remove() }
        listeners = []
        if let ioProcID {
            if isRunning {
                // Synchronous when called off the audio thread: the IOProc won't run again.
                AudioDeviceStop(aggregateID, ioProcID)
                isRunning = false
            }
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        // Only now that no IOProc can use it.
        MPRenderStateDestroy(renderState)
        renderState = nil
    }

    deinit {
        destroy()
    }

    /// A new aggregate device needs a moment before its streams exist; starting IO earlier can
    /// fail silently.
    private func waitUntilReady() throws {
        for _ in 0..<100 {
            if AudioDevices.hasStreams(aggregateID, scope: kAudioObjectPropertyScopeInput),
               AudioDevices.hasStreams(aggregateID, scope: kAudioObjectPropertyScopeOutput) {
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw CoreAudioError(operation: "Wait for aggregate device", status: kAudioHardwareNotRunningError)
    }
}
