/// Folds audio processes into the apps people recognize.
///
/// Rules, in order (the first that finds a running app wins):
/// 1. the process is itself a running app;
/// 2. its responsible process is a running app: maps XPC services such as `com.apple.WebKit.GPU`
///    to Safari or Mail;
/// 3. its parent process is a running app: Chrome and Electron helpers;
/// 4. its bundle ID extends a running app's bundle ID (`net.whatsapp.WhatsApp.ServiceExtension`).
///
/// Processes that belong to no running app (system daemons) are left out, and so are the apps in
/// `hiddenBundleIDs` (Mixpilot itself, system agents that only play feedback sounds).
public enum AppGrouper {
    /// System agents whose sounds aren't worth a row: volume feedback, the charging chime.
    public static let systemAgents: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.PowerChime",
        "com.apple.loginwindow",
    ]

    public static func group(
        _ processes: [AudioProcess],
        runningApps: [RunningApp],
        hiddenBundleIDs: Set<String> = systemAgents,
        hiddenPIDs: Set<Int32> = []
    ) -> [AudioApp] {
        let index = AppIndex(runningApps)
        var apps: [String: AudioApp] = [:]

        for process in processes {
            guard let owner = index.owner(of: process),
                  !hiddenPIDs.contains(owner.pid),
                  !(owner.bundleID.map(hiddenBundleIDs.contains) ?? false)
            else { continue }

            let id = owner.bundleID ?? "pid:\(owner.pid)"
            var app = apps[id] ?? AudioApp(
                id: id,
                bundleID: owner.bundleID,
                pids: [],
                processObjectIDs: [],
                isPlaying: false,
                isUsingMicrophone: false
            )
            if !app.pids.contains(owner.pid) {
                app.pids.append(owner.pid)
                app.pids.sort()
            }
            app.processObjectIDs.append(process.id)
            app.processObjectIDs.sort()
            app.isPlaying = app.isPlaying || process.isRunningOutput
            app.isUsingMicrophone = app.isUsingMicrophone || process.isRunningInput
            apps[id] = app
        }
        return apps.values.sorted { $0.id < $1.id }
    }
}

/// Lookup tables over the running apps.
private struct AppIndex {
    let byPID: [Int32: RunningApp]
    /// Bundle IDs, longest first, so the most specific prefix wins.
    let bundleIDs: [(String, RunningApp)]

    init(_ apps: [RunningApp]) {
        byPID = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        bundleIDs = apps
            .compactMap { app in app.bundleID.map { ($0, app) } }
            .sorted { $0.0.count > $1.0.count }
    }

    func owner(of process: AudioProcess) -> RunningApp? {
        if let app = byPID[process.pid] { return app }
        if let pid = process.responsiblePID, let app = byPID[pid] { return app }
        if let pid = process.parentPID, let app = byPID[pid] { return app }
        if let bundleID = process.bundleID {
            for (appBundleID, app) in bundleIDs where bundleID.hasPrefix(appBundleID + ".") {
                return app
            }
        }
        return nil
    }
}
