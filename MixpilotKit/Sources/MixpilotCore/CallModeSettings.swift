import Foundation

/// How call mode behaves, as set in Settings ▸ Calls.
public struct CallModeSettings: Codable, Sendable, Equatable {
    public static let defaultsKey = "callModeSettings.v1"
    public static let defaultLevel = 0.2

    /// Turn call mode on by itself when a call starts.
    public var isAutomatic: Bool
    /// How loud other apps play during calls: 0…1 of their own volume. Never 0 by default, so
    /// alerts stay audible.
    public var level: Double {
        didSet { level = Self.clamped(level) }
    }
    /// Known call apps and browsers the person doesn't want to start call mode.
    public var excludedApps: Set<String>

    public init(isAutomatic: Bool = true, level: Double = defaultLevel, excludedApps: Set<String> = []) {
        self.isAutomatic = isAutomatic
        self.level = Self.clamped(level)
        self.excludedApps = excludedApps
    }

    /// The apps whose microphone use starts call mode.
    public var callApps: Set<String> {
        KnownCallApps.all.subtracting(excludedApps)
    }

    public static func load(from defaults: UserDefaults = .standard, key: String = defaultsKey) -> CallModeSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(CallModeSettings.self, from: data)
        else { return CallModeSettings() }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard, key: String = defaultsKey) {
        if self == CallModeSettings() {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: key)
        }
    }

    static func clamped(_ level: Double) -> Double {
        guard level.isFinite else { return defaultLevel }
        return min(max(level, 0), 1)
    }

    // Lenient decoding, like `AppAudioSettings`.
    private enum CodingKeys: String, CodingKey {
        case isAutomatic, level, excludedApps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isAutomatic = (try? container.decodeIfPresent(Bool.self, forKey: .isAutomatic)) ?? true
        level = Self.clamped((try? container.decodeIfPresent(Double.self, forKey: .level)) ?? Self.defaultLevel)
        excludedApps = (try? container.decodeIfPresent(Set<String>.self, forKey: .excludedApps)) ?? []
    }
}
