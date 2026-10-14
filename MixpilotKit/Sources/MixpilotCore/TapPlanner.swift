/// One app that Core Audio knows about, with the gain it should have.
public struct TapTarget: Sendable, Equatable {
    public var appID: String
    /// The app's process objects, helpers included.
    public var processObjectIDs: [UInt32]
    /// 1 = unchanged (no tap needed).
    public var gain: Double
    /// The app has an open output stream. Mixpilot only runs audio while it does.
    public var isPlaying: Bool
    /// The device the app plays to (its own choice, or the system default).
    public var outputDeviceUID: String

    public init(appID: String, processObjectIDs: [UInt32], gain: Double, isPlaying: Bool, outputDeviceUID: String) {
        self.appID = appID
        self.processObjectIDs = processObjectIDs
        self.gain = gain
        self.isPlaying = isPlaying
        self.outputDeviceUID = outputDeviceUID
    }

    /// Whether the app needs Mixpilot at all. Apps at 100 % are never tapped.
    public var needsTap: Bool {
        gain != 1
    }
}

/// What the planner needs to know about a running session.
public struct TapSessionState: Sendable, Equatable {
    public var processObjectIDs: [UInt32]
    public var outputDeviceUID: String
    public var gain: Double
    public var isRunning: Bool
    /// Since when the gain has been back at 1. The session is kept for a grace period, so dragging
    /// a slider through 100 % doesn't tear it down and rebuild it.
    public var unitySince: Double?

    public init(processObjectIDs: [UInt32], outputDeviceUID: String, gain: Double, isRunning: Bool, unitySince: Double? = nil) {
        self.processObjectIDs = processObjectIDs
        self.outputDeviceUID = outputDeviceUID
        self.gain = gain
        self.isRunning = isRunning
        self.unitySince = unitySince
    }
}

public enum TapAction: Sendable, Equatable {
    /// Create a session (tap + aggregate device); start audio if the app is playing.
    case create(TapTarget)
    case destroy(appID: String)
    case setGain(appID: String, gain: Double)
    case setProcesses(appID: String, processObjectIDs: [UInt32])
    case start(appID: String)
    case stop(appID: String)
}

/// Decides which sessions to create, change or destroy so the running sessions match the targets.
/// Pure: the caller applies the actions.
public enum TapPlanner {
    /// How long a session survives at 100 % before it is removed.
    public static let unityGrace: Double = 3

    /// - Parameters:
    ///   - targets: every app Core Audio currently knows about.
    ///   - sessions: running sessions by app ID.
    ///   - now: monotonic time in seconds.
    ///   - blocked: apps for which no session may be created right now (recent failure, or no
    ///     permission).
    public static func plan(
        targets: [TapTarget],
        sessions: [String: TapSessionState],
        now: Double,
        blocked: Set<String> = []
    ) -> [TapAction] {
        var actions: [TapAction] = []
        let targetIDs = Set(targets.map(\.appID))

        // Apps that are gone: their processes no longer exist.
        for appID in sessions.keys.sorted() where !targetIDs.contains(appID) {
            actions.append(.destroy(appID: appID))
        }

        for target in targets {
            guard let session = sessions[target.appID] else {
                if target.needsTap && !blocked.contains(target.appID) {
                    actions.append(.create(target))
                }
                continue
            }

            if session.outputDeviceUID != target.outputDeviceUID {
                // The app moved to another device: rebuild there (or just stop if it's at 100 %).
                actions.append(.destroy(appID: target.appID))
                if target.needsTap && !blocked.contains(target.appID) {
                    actions.append(.create(target))
                }
                continue
            }

            if !target.needsTap, let since = session.unitySince, now - since >= unityGrace {
                actions.append(.destroy(appID: target.appID))
                continue
            }

            if session.gain != target.gain {
                actions.append(.setGain(appID: target.appID, gain: target.gain))
            }
            if session.processObjectIDs != target.processObjectIDs {
                actions.append(.setProcesses(appID: target.appID, processObjectIDs: target.processObjectIDs))
            }
            if target.isPlaying && !session.isRunning {
                actions.append(.start(appID: target.appID))
            } else if !target.isPlaying && session.isRunning {
                actions.append(.stop(appID: target.appID))
            }
        }
        return actions
    }

    /// When to plan again for sessions waiting out the grace period at 100 %, if any.
    public static func nextDeadline(sessions: [String: TapSessionState]) -> Double? {
        sessions.values.compactMap { session in
            session.gain == 1 ? session.unitySince.map { $0 + unityGrace } : nil
        }.min()
    }
}
