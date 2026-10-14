/// The volume a person set for one app.
public struct AppVolume: Codable, Sendable, Hashable {
    /// 0 = silent, 1 = as loud as the app plays it, above 1 = boosted.
    public var volume: Double
    public var isMuted: Bool

    public init(volume: Double = 1, isMuted: Bool = false) {
        self.volume = volume
        self.isMuted = isMuted
    }

    /// As the app plays it: nothing to do.
    public static let unchanged = AppVolume()

    /// The gain applied to the app's sound.
    public var gain: Double {
        isMuted ? 0 : volume
    }
}
