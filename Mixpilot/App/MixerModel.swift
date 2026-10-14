import AppKit
import MixpilotAudio
import MixpilotCore
import Observation
import os

/// What one row of the panel shows.
struct AppRowState: Identifiable, Equatable {
    /// Bundle ID (see `AudioApp.id`).
    let id: String
    var name: String
    var icon: NSImage
    var isPlaying: Bool
    var isUsingMicrophone: Bool
    /// Volume, mute and chosen output device.
    var settings: AppAudioSettings = .unchanged
    /// The device the app plays to on its own (Core Audio object ID), if it is playing.
    var ownOutputDeviceID: UInt32?
}

/// The state behind the menu bar panel: which apps are playing sound, their volumes and output
/// devices, and the devices available.
///
/// Turns `ProcessMonitor` snapshots into rows (helpers grouped under their app, a row kept for a
/// few seconds after its app stops playing, sorted by name), remembers each app's settings by
/// bundle ID (`AppSettingsStore`) and tells `TapManager` what every app should sound like.
@Observable
final class MixerModel {
    private(set) var apps: [AppRowState] = []
    private(set) var outputDevices: [OutputDevice] = []
    private(set) var defaultOutputUID: String?
    /// Mixpilot can't change volumes until the System Audio Recording permission is allowed.
    private(set) var needsAudioPermission = false

    @ObservationIgnored private let monitor: ProcessMonitor?
    @ObservationIgnored private let devices: DeviceMonitor?
    @ObservationIgnored private let taps: TapManager?
    @ObservationIgnored private let store: AppSettingsStore?
    @ObservationIgnored private let directory = AppDirectory()
    @ObservationIgnored private let log = Logger(subsystem: "app.mixpilot.mac", category: "mixer")
    @ObservationIgnored private var linger = Linger<String>(duration: 3)
    @ObservationIgnored private var current: [String: AudioApp] = [:]
    @ObservationIgnored private var lastKnown: [String: AppRowState] = [:]
    /// Settings of every app, remembered ones included. Mirrors the store.
    @ObservationIgnored private var settings: [String: AppAudioSettings] = [:]
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var launchObserver: NSObjectProtocol?

    /// The live model. Call `start()` once the app has launched.
    init() {
        monitor = ProcessMonitor()
        devices = DeviceMonitor()
        taps = TapManager()
        let store = AppSettingsStore()
        self.store = store
        settings = store.all
    }

    /// Fixed rows, for previews and snapshots. Never touches Core Audio or saved settings.
    init(previewApps: [AppRowState], devices: [OutputDevice] = [], needsAudioPermission: Bool = false) {
        monitor = nil
        self.devices = nil
        taps = nil
        store = nil
        apps = previewApps
        outputDevices = devices
        defaultOutputUID = devices.first?.id
        settings = Dictionary(uniqueKeysWithValues: previewApps.map { ($0.id, $0.settings) })
        self.needsAudioPermission = needsAudioPermission
    }

    func start() {
        guard let monitor, let devices, let taps, tasks.isEmpty else { return }
        monitor.start()
        devices.start()
        tasks.append(Task { [weak self] in
            for await processes in monitor.processes {
                self?.apply(processes)
            }
        })
        tasks.append(Task { [weak self] in
            for await snapshot in devices.snapshots {
                self?.apply(snapshot)
            }
        })
        tasks.append(Task { [weak self] in
            for await event in taps.events {
                self?.needsAudioPermission = event == .permissionDenied
            }
        })
        // A helper can show up in Core Audio before its app is known to the workspace; group
        // again when an app finishes launching.
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [monitor] _ in
            monitor.republish()
        }
    }

    #if DEBUG
    /// Lets scripts change an app without the panel (debug builds only):
    /// `build/debug-volume <bundle ID> <0…2 | mute | unmute | device <UID | system>>`.
    func installDebugHooks() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("app.mixpilot.debug.volume"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo, let appID = info["app"] as? String else { return }
            let volume = info["volume"] as? Double
            let muted = info["muted"] as? Bool
            let device = info["device"] as? String
            MainActor.assumeIsolated {
                self?.log.info("Debug request for \(appID, privacy: .public)")
                if let volume { self?.setVolume(volume, for: appID) }
                if let muted { self?.setMuted(muted, for: appID) }
                if let device { self?.setOutputDevice(device == "system" ? nil : device, for: appID) }
            }
        }
    }
    #endif

    /// Gives every app its own sound back. Blocks until done: call before quitting.
    func stopAudio() {
        taps?.stopAll()
    }

    // MARK: - Changing an app's settings

    func setVolume(_ volume: Double, for appID: String) {
        change(appID) {
            $0.volume = volume
            // Moving the slider unmutes, as with the system volume.
            $0.isMuted = false
        }
    }

    func setMuted(_ isMuted: Bool, for appID: String) {
        change(appID) { $0.isMuted = isMuted }
    }

    /// Plays the app on the given device (UID), or where it plays on its own for nil.
    func setOutputDevice(_ uid: String?, for appID: String) {
        let name = uid.flatMap { uid in outputDevices.first { $0.id == uid }?.name }
        change(appID) {
            $0.outputDeviceUID = uid
            $0.outputDeviceName = name
        }
    }

    private func change(_ appID: String, _ update: (inout AppAudioSettings) -> Void) {
        var setting = settings[appID] ?? .unchanged
        update(&setting)
        settings[appID] = setting
        store?.set(setting, for: appID)
        if let index = apps.firstIndex(where: { $0.id == appID }) {
            apps[index].settings = setting
            lastKnown[appID] = apps[index]
        }
        sendTapRequests()
    }

    /// Tells the tap manager what every app Core Audio knows should sound like.
    private func sendTapRequests() {
        let requests = current.values.map { app in
            let setting = settings[app.id] ?? .unchanged
            return TapRequest(
                appID: app.id,
                processObjectIDs: app.processObjectIDs,
                gain: setting.gain,
                isPlaying: app.isPlaying,
                outputDeviceIDs: app.outputDeviceIDs,
                preferredOutputUID: setting.outputDeviceUID
            )
        }
        taps?.update(requests)
    }

    // MARK: - Updating from Core Audio

    private func apply(_ snapshot: DeviceSnapshot) {
        outputDevices = snapshot.outputs
        defaultOutputUID = snapshot.defaultOutputUID
        // A chosen device may have connected or disconnected.
        sendTapRequests()
    }

    private func apply(_ processes: [AudioProcess]) {
        log.debug("Snapshot: \(processes.count) processes, \(processes.filter(\.isRunningOutput).count) playing")
        let running = NSWorkspace.shared.runningApplications.map {
            RunningApp(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier)
        }
        let grouped = AppGrouper.group(
            processes,
            runningApps: running,
            hiddenPIDs: [ProcessInfo.processInfo.processIdentifier]
        )
        current = Dictionary(uniqueKeysWithValues: grouped.map { ($0.id, $0) })
        refreshRows()
        sendTapRequests()
    }

    private func refreshRows() {
        let now = ProcessInfo.processInfo.systemUptime
        let active = Set(current.values.filter(\.isPlaying).map(\.id))
        let visible = linger.update(active: active, now: now)

        var rows: [AppRowState] = []
        for id in visible {
            let setting = settings[id] ?? .unchanged
            if let app = current[id] {
                let identity = directory.identity(for: app)
                let row = AppRowState(
                    id: id,
                    name: identity.name,
                    icon: identity.icon,
                    isPlaying: app.isPlaying,
                    isUsingMicrophone: app.isUsingMicrophone,
                    settings: setting,
                    ownOutputDeviceID: app.outputDeviceIDs.first
                )
                lastKnown[id] = row
                rows.append(row)
            } else if var row = lastKnown[id] {
                // The app quit while its row lingers.
                row.isPlaying = false
                row.isUsingMicrophone = false
                rows.append(row)
            }
        }
        lastKnown = lastKnown.filter { visible.contains($0.key) }
        rows.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if rows != apps {
            log.debug("Apps: \(rows.map(\.id).joined(separator: ", "), privacy: .public)")
            apps = rows
        }
        scheduleExpiry(active: active)
    }

    /// Refreshes again when the next lingering row is due to disappear.
    private func scheduleExpiry(active: Set<String>) {
        expiryTask?.cancel()
        guard let expiry = linger.nextExpiry(active: active) else { return }
        let delay = max(0, expiry - ProcessInfo.processInfo.systemUptime) + 0.05
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refreshRows()
        }
    }
}
