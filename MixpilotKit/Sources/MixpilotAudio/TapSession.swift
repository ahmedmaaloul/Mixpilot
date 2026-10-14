import CoreAudio
import Foundation
import MixpilotRender

/// One app's sound, routed through Mixpilot so its volume can change.
///
/// - A private process tap captures the app's processes and mutes their own output only while
///   Mixpilot reads the tap (`.mutedWhenTapped`). If Mixpilot stops reading (the session stops, the
///   app quits, Mixpilot crashes), the app is heard on its own again: a failure never means silence.
/// - A private aggregate device combines the tap (its input) with the app's output device (its
///   output). Private objects are visible only to Mixpilot and vanish with its process.
/// - The C IOProc `MPRenderIOProc` copies input to output with the app's gain.
///
/// Not thread-safe: `TapManager` uses sessions from its queue only.
final class TapSession {
    /// Names Mixpilot's taps and prefixes its aggregate device UIDs, to find leftovers.
    static let tapNamePrefix = "Mixpilot "
    static let aggregateUIDPrefix = "app.mixpilot.tap."

    let appID: String
    let outputDeviceUID: String
    private(set) var processObjectIDs: [AudioObjectID]
    private(set) var gain: Double
    private(set) var isRunning = false
    /// Since when the gain has been back at 1 (see `TapPlanner.unityGrace`).
    var unitySince: Double?

    private let tapDescription: CATapDescription
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var renderState: OpaquePointer?

    init(appID: String, processObjectIDs: [AudioObjectID], gain: Double, outputDeviceUID: String) throws {
        self.appID = appID
        self.processObjectIDs = processObjectIDs
        self.gain = gain
        self.outputDeviceUID = outputDeviceUID

        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.uuid = UUID()
        description.name = Self.tapNamePrefix + appID
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        tapDescription = description

        do {
            try check(AudioHardwareCreateProcessTap(description, &tapID), "Create tap")

            let format = HAL.value(tapID, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
            guard let format, format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32
            else {
                throw CoreAudioError(operation: "Read tap format", status: kAudioHardwareUnsupportedOperationError)
            }
            guard let state = MPRenderStateCreate(Float(gain), format.mSampleRate) else {
                throw CoreAudioError(operation: "Allocate render state", status: kAudio_MemFullError)
            }
            renderState = state

            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Mixpilot",
                kAudioAggregateDeviceUIDKey: Self.aggregateUIDPrefix + description.uuid.uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: false,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: description.uuid.uuidString,
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

    /// Starts audio: from now on the app is heard through Mixpilot.
    func start() throws {
        guard !isRunning, let ioProcID else { return }
        try check(AudioDeviceStart(aggregateID, ioProcID), "Start")
        isRunning = true
    }

    /// Stops audio: the app is heard on its own again (it isn't playing anyway when this is called).
    func stop() {
        guard isRunning, let ioProcID else { return }
        AudioDeviceStop(aggregateID, ioProcID)
        isRunning = false
    }

    func setGain(_ gain: Double) {
        self.gain = gain
        if let renderState {
            MPRenderSetGain(renderState, Float(gain))
        }
    }

    /// Changes which processes are tapped (an app started or stopped a helper), without a gap.
    func setProcesses(_ processObjectIDs: [AudioObjectID]) throws {
        tapDescription.processes = processObjectIDs
        try check(writeDescription(), "Update tap processes")
        self.processObjectIDs = processObjectIDs
    }

    /// Whether audio has ever come through. A tap without the System Audio Recording permission
    /// only delivers silence.
    var hasReceivedSignal: Bool {
        renderState.map(MPRenderHasReceivedSignal) ?? false
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

    /// Tears everything down, in reverse order. Safe to call more than once.
    func destroy() {
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
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
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
