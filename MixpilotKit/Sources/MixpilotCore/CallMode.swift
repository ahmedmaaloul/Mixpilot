/// Apps whose microphone use means "a call is going on".
public enum KnownCallApps {
    /// Call and meeting apps.
    public static let callApps: [String] = [
        "net.whatsapp.WhatsApp",
        "desktop.WhatsApp",                // the older WhatsApp desktop app
        "com.apple.FaceTime",
        "com.apple.mobilephone",           // Phone (calls through iPhone)
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "Cisco-Systems.Spark",             // Webex
        "com.webex.meetingmanager",        // Webex Meetings
        "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",       // Slack huddles
        "ru.keepcoder.Telegram",
        "org.telegram.desktop",
        "com.facebook.archon",             // Messenger
        "org.whispersystems.signal-desktop",
        "com.skype.skype",
    ]

    /// Browsers: a tab with the microphone on (Google Meet, Teams on the web) is a call.
    public static let browsers: [String] = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "company.thebrowser.Browser",      // Arc
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "com.duckduckgo.macos.browser",
    ]

    public static var all: Set<String> {
        Set(callApps + browsers)
    }
}

/// Decides when call mode is on: other apps are lowered while it is.
///
/// - **Automatic**: a call is detected when a call app (`callApps`) has used the microphone for
///   `startDelay` seconds, so a quick microphone check doesn't count. It ends when no call app has
///   used the microphone for `endDelay` seconds, so muting yourself for a moment or a device switch
///   doesn't end it.
/// - **Manual**: the switch in the panel (or a shortcut) always wins. Turning it on or off overrides
///   detection until a call starts or ends, then automatic takes over again, so the next call is
///   handled even if the switch was used during the last one.
///
/// Pure: time is passed in (monotonic seconds) and the caller re-evaluates at `nextDeadline()`.
public struct CallMode: Sendable, Equatable {
    public struct Configuration: Sendable, Equatable {
        public var callApps: Set<String>
        /// Turn call mode on by itself when a call starts.
        public var isAutomatic: Bool
        public var startDelay: Double
        public var endDelay: Double

        public init(callApps: Set<String> = KnownCallApps.all, isAutomatic: Bool = true, startDelay: Double = 1, endDelay: Double = 5) {
            self.callApps = callApps
            self.isAutomatic = isAutomatic
            self.startDelay = startDelay
            self.endDelay = endDelay
        }
    }

    public var configuration: Configuration
    /// A call app is using the microphone (after the delays).
    public private(set) var isCallDetected = false
    /// The apps in the detected call. They are never lowered.
    public private(set) var callAppIDs: Set<String> = []
    /// What the person chose with the switch, until a call starts or ends.
    public private(set) var manualOverride: Bool?

    /// Since when a call app has been using the microphone, before the call counts.
    private var candidateSince: Double?
    /// Since when no call app has been using the microphone, during a call.
    private var idleSince: Double?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Whether other apps are lowered right now.
    public var isActive: Bool {
        manualOverride ?? (configuration.isAutomatic && isCallDetected)
    }

    /// The person flipped the switch.
    public mutating func setManually(_ isOn: Bool) {
        manualOverride = isOn
    }

    /// Feeds the apps using the microphone right now. Call it whenever they change and at
    /// `nextDeadline()`.
    public mutating func update(microphoneUsers: Set<String>, now: Double) {
        let inCall = microphoneUsers.intersection(configuration.callApps)
        if inCall.isEmpty {
            candidateSince = nil
            guard isCallDetected else { return }
            let since = idleSince ?? now
            idleSince = since
            if now - since >= configuration.endDelay {
                isCallDetected = false
                callAppIDs = []
                idleSince = nil
                manualOverride = nil
            }
            return
        }

        idleSince = nil
        if isCallDetected {
            callAppIDs.formUnion(inCall)
            return
        }
        let since = candidateSince ?? now
        candidateSince = since
        if now - since >= configuration.startDelay {
            isCallDetected = true
            callAppIDs = inCall
            candidateSince = nil
            manualOverride = nil
        }
    }

    /// When `update` must run again even if nothing changes (a delay running out), if ever.
    public func nextDeadline() -> Double? {
        if let since = candidateSince {
            return since + configuration.startDelay
        }
        if isCallDetected, let since = idleSince {
            return since + configuration.endDelay
        }
        return nil
    }
}
