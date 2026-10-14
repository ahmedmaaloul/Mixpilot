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
}

/// The state behind the menu bar panel: which apps are playing sound, live.
///
/// Turns `ProcessMonitor` snapshots into rows: groups helper processes under their app, keeps a
/// row for a few seconds after its app stops playing (so the list doesn't jump between tracks)
/// and sorts rows by name.
@Observable
final class MixerModel {
    private(set) var apps: [AppRowState] = []

    @ObservationIgnored private let monitor: ProcessMonitor?
    @ObservationIgnored private let directory = AppDirectory()
    @ObservationIgnored private let log = Logger(subsystem: "app.mixpilot.mac", category: "mixer")
    @ObservationIgnored private var linger = Linger<String>(duration: 3)
    @ObservationIgnored private var current: [String: AudioApp] = [:]
    @ObservationIgnored private var lastKnown: [String: AppRowState] = [:]
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var launchObserver: NSObjectProtocol?

    /// The live model. Call `start()` once the app has launched.
    init() {
        monitor = ProcessMonitor()
    }

    /// Fixed rows, for previews and snapshots. Never touches Core Audio.
    init(previewApps: [AppRowState]) {
        monitor = nil
        apps = previewApps
    }

    func start() {
        guard let monitor, listenTask == nil else { return }
        monitor.start()
        listenTask = Task { [weak self] in
            for await processes in monitor.processes {
                self?.apply(processes)
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
    }

    private func refreshRows() {
        let now = ProcessInfo.processInfo.systemUptime
        let active = Set(current.values.filter(\.isPlaying).map(\.id))
        let visible = linger.update(active: active, now: now)

        var rows: [AppRowState] = []
        for id in visible {
            if let app = current[id] {
                let identity = directory.identity(for: app)
                let row = AppRowState(
                    id: id,
                    name: identity.name,
                    icon: identity.icon,
                    isPlaying: app.isPlaying,
                    isUsingMicrophone: app.isUsingMicrophone
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
