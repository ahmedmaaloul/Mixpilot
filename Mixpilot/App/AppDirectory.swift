import AppKit
import MixpilotCore
import UniformTypeIdentifiers

/// Names and icons of apps, as Finder and the Dock show them. Cached by app ID.
final class AppDirectory {
    struct Identity {
        let name: String
        let icon: NSImage
    }

    private var cache: [String: Identity] = [:]

    func identity(for app: AudioApp) -> Identity {
        if let cached = cache[app.id] { return cached }

        let running = app.pids.lazy.compactMap { NSRunningApplication(processIdentifier: $0) }.first
        let url = running?.bundleURL
            ?? app.bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }?
                .resolvingSymlinksInPath()
        let name = running?.localizedName
            ?? url.map { FileManager.default.displayName(atPath: $0.path) }
            ?? app.bundleID
            ?? String(localized: "Unknown App")
        let icon = running?.icon
            ?? url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .application)

        let identity = Identity(name: name, icon: icon)
        cache[app.id] = identity
        return identity
    }

    /// For apps that may not be running (remembered apps, call apps in Settings).
    func identity(forBundleID bundleID: String) -> Identity {
        identity(for: AudioApp(id: bundleID, bundleID: bundleID, pids: [], processObjectIDs: [], isPlaying: false, isUsingMicrophone: false))
    }

    /// Whether an app with this bundle ID is installed.
    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}
