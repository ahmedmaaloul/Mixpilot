import CoreAudio
import Foundation
import MixpilotRender
import os

/// The System Audio Recording permission ("Screen & System Audio Recording ▸ System Audio Recording
/// Only" in System Settings). There is no public API for its status, so it is probed with a tap.
public enum AudioPermission {
    /// Whether Mixpilot may capture app audio. Creates a private tap that mutes nothing and is
    /// never read, rewrites its description and destroys it: `kAudioDevicePermissionsError` means no.
    /// Before the person was asked, this also says no.
    public static func isGranted() -> Bool {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.isPrivate = true
        description.muteBehavior = .unmuted
        description.name = TapSession.tapNamePrefix + "permission check"
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr, tap != kAudioObjectUnknown else { return false }
        defer { AudioHardwareDestroyProcessTap(tap) }
        var address = HAL.address(kAudioTapPropertyDescription)
        var reference = Unmanaged.passUnretained(description)
        let status = AudioObjectSetPropertyData(
            tap, &address, 0, nil, UInt32(MemoryLayout<Unmanaged<CATapDescription>>.size), &reference
        )
        return status != kAudioDevicePermissionsError
    }

    /// Shows the system's permission prompt (it appears the first time a tap is read) and reports
    /// once the permission is granted, or after `timeout` seconds with `false`.
    ///
    /// The tap used for this captures all apps but mutes none, and its audio is replaced by silence,
    /// so nothing anyone hears changes.
    public static func request(timeout: Double = 60) async -> Bool {
        if isGranted() { return true }
        let request = PromptingTap()
        defer { request.stop() }
        guard request.start() else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(for: .seconds(1))
            if isGranted() { return true }
        }
        return false
    }
}

/// A tap read just long enough to make macOS ask for the permission. Silent: it outputs zeros.
private final class PromptingTap {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var state: OpaquePointer?

    func start() -> Bool {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        description.name = TapSession.tapNamePrefix + "permission request"
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr, tap != kAudioObjectUnknown,
              let output = AudioDevices.defaultOutput().flatMap(AudioDevices.uid(of:)),
              let state = MPRenderStateCreate(0, 0, 48_000)
        else {
            Logger.mixpilot("permission").error("Couldn't set up the permission request")
            return false
        }
        self.state = state
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Mixpilot",
            kAudioAggregateDeviceUIDKey: TapSession.aggregateUIDPrefix + description.uuid.uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate) == noErr,
              AudioDeviceCreateIOProcID(aggregate, MPRenderIOProc, UnsafeMutableRawPointer(state), &ioProc) == noErr,
              let ioProc
        else { return false }
        return AudioDeviceStart(aggregate, ioProc) == noErr
    }

    func stop() {
        if let ioProc {
            AudioDeviceStop(aggregate, ioProc)
            AudioDeviceDestroyIOProcID(aggregate, ioProc)
            self.ioProc = nil
        }
        if aggregate != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregate)
            aggregate = AudioObjectID(kAudioObjectUnknown)
        }
        if tap != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tap)
            tap = AudioObjectID(kAudioObjectUnknown)
        }
        MPRenderStateDestroy(state)
        state = nil
    }
}
