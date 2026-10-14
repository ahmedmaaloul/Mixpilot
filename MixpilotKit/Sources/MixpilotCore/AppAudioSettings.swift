/// What a person set for one app: its volume, whether it is muted, and where it plays.
public struct AppAudioSettings: Codable, Sendable, Hashable {
    /// 0 = silent, 1 = as loud as the app plays it, up to 2 = boosted to 200 %.
    public static let volumeRange: ClosedRange<Double> = 0...2

    public var volume: Double {
        didSet { volume = Self.clamped(volume) }
    }
    public var isMuted: Bool
    /// The output device chosen for this app (its UID), or nil to use the system setting.
    public var outputDeviceUID: String?
    /// The chosen device's name, to show it while it isn't connected.
    public var outputDeviceName: String?

    public init(volume: Double = 1, isMuted: Bool = false, outputDeviceUID: String? = nil, outputDeviceName: String? = nil) {
        self.volume = Self.clamped(volume)
        self.isMuted = isMuted
        self.outputDeviceUID = outputDeviceUID
        self.outputDeviceName = outputDeviceUID == nil ? nil : outputDeviceName
    }

    /// As the app plays it on its own: nothing to do, nothing to remember.
    public static let unchanged = AppAudioSettings()

    public var isUnchanged: Bool {
        self == .unchanged
    }

    /// The gain applied to the app's sound.
    public var gain: Double {
        isMuted ? 0 : volume
    }

    /// Values within 3 % of 100 % become exactly 100 %, so dragging back to the middle tick really
    /// gives the app its own level back (and releases it).
    public static func snapped(_ volume: Double) -> Double {
        abs(volume - 1) < 0.03 ? 1 : volume
    }

    static func clamped(_ volume: Double) -> Double {
        guard volume.isFinite else { return 1 }
        return min(max(volume, volumeRange.lowerBound), volumeRange.upperBound)
    }

    // Lenient decoding: missing or invalid values fall back to the defaults, so stored settings
    // from older or newer versions never fail to load.
    private enum CodingKeys: String, CodingKey {
        case volume, isMuted, outputDeviceUID, outputDeviceName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        volume = Self.clamped((try? container.decodeIfPresent(Double.self, forKey: .volume)) ?? 1)
        isMuted = (try? container.decodeIfPresent(Bool.self, forKey: .isMuted)) ?? false
        let uid = try? container.decodeIfPresent(String.self, forKey: .outputDeviceUID)
        outputDeviceUID = uid?.isEmpty == false ? uid : nil
        outputDeviceName = outputDeviceUID == nil ? nil : (try? container.decodeIfPresent(String.self, forKey: .outputDeviceName)) ?? nil
    }
}
