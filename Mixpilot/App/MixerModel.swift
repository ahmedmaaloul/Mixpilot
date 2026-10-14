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
    /// 0…1 (boost above 1 arrives with M3).
    var volume: Double = 1
    var isMuted = false
}

/// The state behind the menu bar panel: which apps are playing sound, and their volumes.
///
/// Turns `ProcessMonitor` snapshots into rows (helpers grouped under their app, a row kept for a
/// few seconds after its app stops playing, sorted by name) and tells `TapManager` which apps
/// need their volume changed.
@Observable
final class MixerModel {
    private(set) var apps: [AppRowState] = []
    /// Mixpilot can't change volumes until the System Audio Recording permission is allowed.
    private(set) var needsAudioPermission = false

    @ObservationIgnored private let monitor: ProcessMonitor?
    @ObservationIgnored private let taps: TapManager?
    @ObservationIgnored private let directory = AppDirectory()
    @ObservationIgnored private let log = Logger(subsystem: "app.mixpilot.mac", category: "mixer")
    @ObservationIgnored private var linger = Linger<String>(duration: 3)
    @ObservationIgnored private var current: [String: AudioApp] = [:]
    @ObservationIgnored private var lastKnown: [String: AppRowState] = [:]
    @ObservationIgnored private var volumes: [String: AppVolume] = [:]
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var launchObserver: NSObjectProtocol?

    /// The live model. Call `start()` once the app has launched.
    init() {
        monitor = ProcessMonitor()
        taps = TapManager()
    }

    /// Fixed rows, for previews and snapshots. Never touches Core Audio.
    init(previewApps: [AppRowState], needsAudioPermission: Bool = false) {
        monitor = nil
        taps = nil
        apps = previewApps
        self.needsAudioPermission = needsAudioPermission
    }

    func start() {
        guard let monitor, let taps, listenTask == nil else { return }
        monitor.start()
        listenTask = Task { [weak self] in
            for await processes in monitor.processes {
                self?.apply(processes)
            }
        }
        eventTask = Task { [weak self] in
            for await event in taps.events {
                self?.needsAudioPermission = event == .permissionDenied
            }
        }
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
    /// Lets scripts change volumes without the panel (debug builds only):
    /// `scripts/debug-volume.swift <bundle ID> <volume 0…1 | mute | unmute>`.
    func installDebugHooks() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("app.mixpilot.debug.volume"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo, let appID = info["app"] as? String else { return }
            let volume = info["volume"] as? Double
            let muted = info["muted"] as? Bool
            MainActor.assumeIsolated {
                self?.log.info("Debug request for \(appID, privacy: .public)")
                if let volume { self?.setVolume(volume, for: appID) }
                if let muted { self?.setMuted(muted, for: appID) }
            }
        }
    }
    #endif

    /// Gives every app its own sound back. Blocks until done: call before quitting.
    func stopAudio() {
        taps?.stopAll()
    }

    // MARK: - Volume

    func setVolume(_ volume: Double, for appID: String) {
        var setting = volumes[appID] ?? .unchanged
        setting.volume = min(max(volume, 0), 1)
        // Moving the slider unmutes, as with the system volume.
        setting.isMuted = false
        volumes[appID] = setting
        updateRow(appID, with: setting)
        sendTapRequests()
    }

    func setMuted(_ isMuted: Bool, for appID: String) {
        var setting = volumes[appID] ?? .unchanged
        setting.isMuted = isMuted
        volumes[appID] = setting
        updateRow(appID, with: setting)
        sendTapRequests()
    }

    private func updateRow(_ appID: String, with setting: AppVolume) {
        guard let index = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[index].volume = setting.volume
        apps[index].isMuted = setting.isMuted
        lastKnown[appID] = apps[index]
    }

    /// Tells the tap manager what every app Core Audio knows should sound like.
    private func sendTapRequests() {
        let requests = current.values.map { app in
            TapRequest(
                appID: app.id,
                processObjectIDs: app.processObjectIDs,
                gain: (volumes[app.id] ?? .unchanged).gain,
                isPlaying: app.isPlaying,
                outputDeviceIDs: app.outputDeviceIDs
            )
        }
        taps?.update(requests)
    }

    // MARK: - Updating rows

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
            let setting = volumes[id] ?? .unchanged
            if let app = current[id] {
                let identity = directory.identity(for: app)
                let row = AppRowState(
                    id: id,
                    name: identity.name,
                    icon: identity.icon,
                    isPlaying: app.isPlaying,
                    isUsingMicrophone: app.isUsingMicrophone,
                    volume: setting.volume,
                    isMuted: setting.isMuted
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
