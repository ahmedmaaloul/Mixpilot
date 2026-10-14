import Foundation

/// Remembers each app's audio settings by bundle ID, so they apply again the next time the app
/// plays sound.
///
/// Stored as one JSON value in UserDefaults. Apps at their unchanged settings aren't stored, and
/// neither are apps without a bundle ID (their identifier changes with every launch).
public final class AppSettingsStore {
    public static let defaultsKey = "appAudioSettings.v1"

    public private(set) var all: [String: AppAudioSettings]

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
        all = Self.load(from: defaults, key: key)
    }

    public subscript(appID: String) -> AppAudioSettings {
        all[appID] ?? .unchanged
    }

    public func set(_ settings: AppAudioSettings, for appID: String) {
        guard Self.isRememberable(appID) else { return }
        let value: AppAudioSettings? = settings.isUnchanged ? nil : settings
        guard all[appID] != value else { return }
        all[appID] = value
        save()
    }

    public func remove(_ appID: String) {
        guard all.removeValue(forKey: appID) != nil else { return }
        save()
    }

    public func removeAll() {
        all = [:]
        defaults.removeObject(forKey: key)
    }

    /// Bundle IDs only; `pid:` identifiers are per launch.
    public static func isRememberable(_ appID: String) -> Bool {
        !appID.isEmpty && !appID.hasPrefix("pid:")
    }

    private func save() {
        if all.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: key)
        }
    }

    /// Unreadable data is ignored rather than crashing; entries are validated one by one.
    private static func load(from defaults: UserDefaults, key: String) -> [String: AppAudioSettings] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: AppAudioSettings].self, from: data)
        else { return [:] }
        return decoded.filter { isRememberable($0.key) && !$0.value.isUnchanged }
    }
}
