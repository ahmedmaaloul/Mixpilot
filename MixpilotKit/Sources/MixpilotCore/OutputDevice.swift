/// An audio output device as the panel shows it.
public struct OutputDevice: Sendable, Hashable, Identifiable {
    /// The device UID: stable across launches and reconnections, so it can be remembered.
    public var id: String
    /// The Core Audio object ID: valid while the device is connected.
    public var objectID: UInt32
    public var name: String
    public var kind: Kind

    public init(id: String, objectID: UInt32, name: String, kind: Kind) {
        self.id = id
        self.objectID = objectID
        self.name = name
        self.kind = kind
    }

    /// What the device is, to pick its symbol.
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case macBookSpeakers, iMacSpeakers, macMiniSpeakers, macStudioSpeakers, displaySpeakers
        case builtInSpeakers, headphones
        case airPods, airPodsPro, airPodsMax, beats, bluetooth
        case tv, airPlay, homePod, usb, virtual, other

        /// Classifies a device from its transport type (Core Audio four-character code), its name
        /// and, for built-in outputs, whether the headphone jack is in use.
        public static func classify(transport: UInt32, name: String, isHeadphoneJack: Bool = false) -> Kind {
            switch transport {
            case Transport.builtIn:
                if isHeadphoneJack { return .headphones }
                if name.contains("MacBook") { return .macBookSpeakers }
                if name.contains("iMac") { return .iMacSpeakers }
                if name.contains("Mac mini") { return .macMiniSpeakers }
                if name.contains("Mac Studio") { return .macStudioSpeakers }
                return .builtInSpeakers
            case Transport.bluetooth, Transport.bluetoothLE:
                if name.contains("AirPods Max") { return .airPodsMax }
                if name.contains("AirPods Pro") { return .airPodsPro }
                if name.contains("AirPods") { return .airPods }
                if name.contains("Beats") || name.contains("Powerbeats") { return .beats }
                return .bluetooth
            case Transport.hdmi, Transport.displayPort, Transport.thunderbolt:
                // Apple displays with speakers show up as DisplayPort or Thunderbolt too.
                if name.contains("Display") { return .displaySpeakers }
                return .tv
            case Transport.airPlay:
                return name.contains("HomePod") ? .homePod : .airPlay
            case Transport.usb:
                if name.contains("Display") { return .displaySpeakers }
                return .usb
            case Transport.virtual, Transport.aggregate:
                return .virtual
            default:
                return .other
            }
        }
    }

    /// Core Audio transport types (`kAudioDeviceTransportType…`), without importing Core Audio.
    public enum Transport {
        public static let builtIn = fourCC("bltn")
        public static let bluetooth = fourCC("blue")
        public static let bluetoothLE = fourCC("blea")
        public static let hdmi = fourCC("hdmi")
        public static let displayPort = fourCC("dprt")
        public static let thunderbolt = fourCC("thun")
        public static let airPlay = fourCC("airp")
        public static let usb = fourCC("usb ")
        public static let virtual = fourCC("virt")
        public static let aggregate = fourCC("grup")

        static func fourCC(_ code: String) -> UInt32 {
            code.utf8.reduce(0) { $0 << 8 | UInt32($1) }
        }
    }
}
