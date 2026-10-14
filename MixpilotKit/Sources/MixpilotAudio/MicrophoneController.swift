import CoreAudio
import Foundation
import os

/// The current input device, as the panel shows it.
public struct MicrophoneState: Sendable, Equatable {
    public var deviceName: String?
    /// Input volume 0…1, or nil if the device's level can't be changed.
    public var volume: Double?
    /// Muted by Mixpilot.
    public var isMuted: Bool
    /// The device can be muted (it has a mute switch or an adjustable level).
    public var canMute: Bool

    public init(deviceName: String? = nil, volume: Double? = nil, isMuted: Bool = false, canMute: Bool = false) {
        self.deviceName = deviceName
        self.volume = volume
        self.isMuted = isMuted
        self.canMute = canMute
    }
}

/// Mutes the microphone and sets its input volume: always the system's current input device.
///
/// Muting uses the device's own mute switch when it has one; otherwise its input volume goes to 0
/// and the previous level is remembered. The mute follows the input device when it changes, and
/// it never outlives Mixpilot: `restoreAll()` runs when Mixpilot quits, and devices left muted by
/// a crash are restored at the next launch (`restoreLeftovers`), so no one is left with a
/// microphone they can't unmute anywhere in macOS.
public final class MicrophoneController: @unchecked Sendable {
    public let states: AsyncStream<MicrophoneState>

    private let continuation: AsyncStream<MicrophoneState>.Continuation
    private let queue = DispatchQueue(label: "app.mixpilot.microphone", qos: .userInitiated)
    private let defaults: UserDefaults
    private let log = Logger.mixpilot("microphone")

    // Confined to `queue`.
    private var wantsMute = false
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var systemListener: HALListener?
    private var deviceListeners: [HALListener] = []
    private var last: MicrophoneState?

    /// Devices Mixpilot muted, by UID: `-1` for the device's mute switch, else the volume to restore.
    static let mutedDevicesKey = "mutedInputDevices"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        (states, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Unmutes microphones an earlier run of Mixpilot left muted (it quit unexpectedly).
    public static func restoreLeftovers(defaults: UserDefaults = .standard) {
        guard let muted = defaults.dictionary(forKey: mutedDevicesKey) as? [String: Double], !muted.isEmpty else { return }
        for (uid, saved) in muted {
            if let device = AudioDevices.device(forUID: uid) {
                InputLevel(device: device).restore(saved)
            }
        }
        defaults.removeObject(forKey: mutedDevicesKey)
        Logger.mixpilot("microphone").notice("Unmuted \(muted.count) microphone(s) left muted")
    }

    public func start() {
        queue.async { [self] in
            guard systemListener == nil else { return }
            systemListener = HALListener(
                object: HAL.systemObject,
                selector: kAudioHardwarePropertyDefaultInputDevice,
                queue: queue
            ) { [weak self] in
                self?.defaultInputChanged()
            }
            defaultInputChanged()
        }
    }

    public func setMuted(_ muted: Bool) {
        queue.async { [self] in
            wantsMute = muted
            if muted {
                mute(device)
            } else {
                unmute(device)
            }
            publish()
        }
    }

    /// Sets the input volume (0…1). Changing it unmutes, as with app volumes.
    public func setVolume(_ volume: Double) {
        queue.async { [self] in
            if wantsMute {
                wantsMute = false
                unmute(device)
            }
            InputLevel(device: device).setVolume(min(max(volume, 0), 1))
            publish()
        }
    }

    /// Gives every microphone its own state back. Blocks until done: call before quitting.
    public func restoreAll() {
        queue.sync {
            unmute(device)
            wantsMute = false
            Self.restoreLeftovers(defaults: defaults)
        }
    }

    // MARK: - On the queue

    private func defaultInputChanged() {
        let newDevice = HAL.value(HAL.systemObject, kAudioHardwarePropertyDefaultInputDevice, initial: AudioObjectID(kAudioObjectUnknown))
            ?? AudioObjectID(kAudioObjectUnknown)
        guard newDevice != device else { return }
        // The mute moves with the input device.
        if wantsMute {
            unmute(device)
        }
        device = newDevice
        if wantsMute {
            mute(device)
        }
        deviceListeners.forEach { $0.remove() }
        deviceListeners = []
        if device != kAudioObjectUnknown {
            // Reflect changes made in System Settings or by other apps.
            for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                for element in [kAudioObjectPropertyElementMain, 1, 2] {
                    if let listener = HALListener(
                        object: device, selector: selector, scope: kAudioObjectPropertyScopeInput,
                        element: element, queue: queue, handler: { [weak self] in self?.publish() }
                    ) {
                        deviceListeners.append(listener)
                    }
                }
            }
        }
        publish()
    }

    private func mute(_ device: AudioObjectID) {
        guard device != kAudioObjectUnknown, let uid = AudioDevices.uid(of: device) else { return }
        var muted = defaults.dictionary(forKey: Self.mutedDevicesKey) as? [String: Double] ?? [:]
        guard muted[uid] == nil else { return }
        let level = InputLevel(device: device)
        if level.canSetMute {
            level.setMute(true)
            muted[uid] = -1
        } else if let volume = level.volume, level.canSetVolume {
            level.setVolume(0)
            muted[uid] = volume
        } else {
            log.notice("The input device can't be muted")
            return
        }
        // Written before anything else can go wrong, so a crash can be undone at the next launch.
        defaults.set(muted, forKey: Self.mutedDevicesKey)
    }

    private func unmute(_ device: AudioObjectID) {
        guard device != kAudioObjectUnknown, let uid = AudioDevices.uid(of: device) else { return }
        var muted = defaults.dictionary(forKey: Self.mutedDevicesKey) as? [String: Double] ?? [:]
        guard let saved = muted.removeValue(forKey: uid) else { return }
        InputLevel(device: device).restore(saved)
        if muted.isEmpty {
            defaults.removeObject(forKey: Self.mutedDevicesKey)
        } else {
            defaults.set(muted, forKey: Self.mutedDevicesKey)
        }
    }

    private func publish() {
        var state = MicrophoneState()
        if device != kAudioObjectUnknown {
            let level = InputLevel(device: device)
            // Mixpilot's own record says whether it muted this device, and at what volume.
            let saved = AudioDevices.uid(of: device).flatMap { (defaults.dictionary(forKey: Self.mutedDevicesKey) as? [String: Double])?[$0] }
            state.deviceName = HAL.string(device, kAudioObjectPropertyName)
            state.isMuted = saved != nil
            state.canMute = level.canSetMute || level.canSetVolume
            if level.canSetVolume {
                // While muted through the volume, show the level it will come back to.
                state.volume = saved.flatMap { $0 >= 0 ? $0 : nil } ?? level.volume
            }
        }
        guard state != last else { return }
        last = state
        continuation.yield(state)
    }
}

/// The input volume and mute of one device. Devices expose them on the main element or per
/// channel; this hides the difference.
private struct InputLevel {
    let device: AudioObjectID

    private static let scope = kAudioObjectPropertyScopeInput

    /// Elements that carry the volume: the main one if it exists, else channels 1 and 2.
    private var volumeElements: [AudioObjectPropertyElement] {
        if has(kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        return [1, 2].filter { has(kAudioDevicePropertyVolumeScalar, element: $0) }
    }

    var volume: Double? {
        guard let element = volumeElements.first else { return nil }
        var address = HAL.address(kAudioDevicePropertyVolumeScalar, scope: Self.scope, element: element)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    var canSetVolume: Bool {
        guard let element = volumeElements.first else { return false }
        return isSettable(kAudioDevicePropertyVolumeScalar, element: element)
    }

    var canSetMute: Bool {
        has(kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)
            && isSettable(kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)
    }

    func setVolume(_ volume: Double) {
        for element in volumeElements {
            var address = HAL.address(kAudioDevicePropertyVolumeScalar, scope: Self.scope, element: element)
            var value = Float32(volume)
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    func setMute(_ muted: Bool) {
        var address = HAL.address(kAudioDevicePropertyMute, scope: Self.scope, element: kAudioObjectPropertyElementMain)
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    /// Undoes a mute: `-1` clears the mute switch, any other value is the volume to restore.
    func restore(_ saved: Double) {
        if saved < 0 {
            setMute(false)
        } else {
            setVolume(saved)
        }
    }

    private func has(_ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> Bool {
        var address = HAL.address(selector, scope: Self.scope, element: element)
        return AudioObjectHasProperty(device, &address)
    }

    private func isSettable(_ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> Bool {
        var address = HAL.address(selector, scope: Self.scope, element: element)
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }
}
