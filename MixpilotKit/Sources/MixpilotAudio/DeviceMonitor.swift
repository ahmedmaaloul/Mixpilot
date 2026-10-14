import CoreAudio
import Foundation
import MixpilotCore

/// The output devices and the system's default output, as of now.
public struct DeviceSnapshot: Sendable, Equatable {
    /// Devices that can play sound, sorted by name. Mixpilot's own devices are left out.
    public var outputs: [OutputDevice]
    public var defaultOutputUID: String?

    public init(outputs: [OutputDevice] = [], defaultOutputUID: String? = nil) {
        self.outputs = outputs
        self.defaultOutputUID = defaultOutputUID
    }
}

/// Watches the output devices (headphones plugged in, AirPods connecting, the default output
/// changing) and publishes a fresh snapshot after each change.
public final class DeviceMonitor: @unchecked Sendable {
    public let snapshots: AsyncStream<DeviceSnapshot>

    private let continuation: AsyncStream<DeviceSnapshot>.Continuation
    private let queue = DispatchQueue(label: "app.mixpilot.device-monitor", qos: .userInitiated)

    // Confined to `queue`.
    private var systemListeners: [HALListener] = []
    private var deviceListeners: [AudioObjectID: [HALListener]] = [:]
    private var isPublishScheduled = false
    private var last: DeviceSnapshot?

    public init() {
        (snapshots, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    public func start() {
        queue.async { [self] in
            guard systemListeners.isEmpty else { return }
            systemListeners = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice].compactMap {
                HALListener(object: HAL.systemObject, selector: $0, queue: queue) { [weak self] in
                    self?.refresh()
                }
            }
            refresh()
        }
    }

    public func stop() {
        queue.sync {
            systemListeners.forEach { $0.remove() }
            systemListeners = []
            deviceListeners.values.joined().forEach { $0.remove() }
            deviceListeners = [:]
        }
        continuation.finish()
    }

    /// The current snapshot, read synchronously (for the tap manager).
    static func current() -> DeviceSnapshot {
        let outputs = AudioDevices.all()
            .compactMap(outputDevice)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return DeviceSnapshot(outputs: outputs, defaultOutputUID: AudioDevices.defaultOutput().flatMap(AudioDevices.uid(of:)))
    }

    // MARK: - On the queue

    private func refresh() {
        let devices = Set(AudioDevices.all())
        for gone in deviceListeners.keys where !devices.contains(gone) {
            deviceListeners.removeValue(forKey: gone)?.forEach { $0.remove() }
        }
        for device in devices where deviceListeners[device] == nil {
            // The built-in output switches between speakers and headphones by data source;
            // names change when a device is renamed.
            let watched: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
                (kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput),
                (kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal),
            ]
            deviceListeners[device] = watched.compactMap { selector, scope in
                HALListener(object: device, selector: selector, scope: scope, queue: queue) { [weak self] in
                    self?.scheduleSnapshot()
                }
            }
        }
        scheduleSnapshot()
    }

    private func scheduleSnapshot() {
        guard !isPublishScheduled else { return }
        isPublishScheduled = true
        // Connecting a device changes several properties in a row; publish once.
        queue.asyncAfter(deadline: .now() + .milliseconds(100)) { [self] in
            isPublishScheduled = false
            let snapshot = Self.current()
            guard snapshot != last else { return }
            last = snapshot
            continuation.yield(snapshot)
        }
    }

    static func outputDevice(_ device: AudioObjectID) -> OutputDevice? {
        guard AudioDevices.hasStreams(device, scope: kAudioObjectPropertyScopeOutput),
              HAL.value(device, kAudioDevicePropertyIsHidden, initial: UInt32(0)) != 1,
              let uid = AudioDevices.uid(of: device),
              !uid.hasPrefix(TapSession.aggregateUIDPrefix)
        else { return nil }
        let name = HAL.string(device, kAudioObjectPropertyName) ?? uid
        let transport = HAL.value(device, kAudioDevicePropertyTransportType, initial: UInt32(0)) ?? 0
        let dataSource = HAL.value(device, kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput, initial: UInt32(0))
        let kind = OutputDevice.Kind.classify(
            transport: transport,
            name: name,
            isHeadphoneJack: dataSource == OutputDevice.Transport.headphoneDataSource
        )
        return OutputDevice(id: uid, objectID: device, name: name, kind: kind)
    }
}

extension OutputDevice.Transport {
    /// `kIOAudioOutputPortSubTypeHeadphones`: the built-in output's headphone jack.
    static let headphoneDataSource: UInt32 = 0x6864_706E // 'hdpn'
}
