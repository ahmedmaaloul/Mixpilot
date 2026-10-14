/// One client process of the audio system, as Core Audio reports it.
///
/// Browsers, Electron apps and WebKit play sound from helper processes, so a process is not the
/// same as an app: `AppGrouper` folds processes into `AudioApp`s.
public struct AudioProcess: Sendable, Hashable, Identifiable {
    /// The Core Audio process object (`AudioObjectID`). Stable while the process runs.
    public var id: UInt32
    public var pid: Int32
    /// Bundle ID of the process itself, which for helpers is not the app's (`com.google.Chrome.helper`).
    public var bundleID: String?
    /// The process has at least one active output stream. Not the same as audible: some apps keep
    /// streams open for a while after pausing.
    public var isRunningOutput: Bool
    /// The process has at least one active input stream (it is using a microphone).
    public var isRunningInput: Bool
    /// The parent process, if it isn't launchd.
    public var parentPID: Int32?
    /// The process macOS holds responsible for this one (XPC services → the app that uses them).
    public var responsiblePID: Int32?
    /// Output devices the process is playing to (`AudioObjectID`s), usually one.
    public var outputDeviceIDs: [UInt32]

    public init(
        id: UInt32,
        pid: Int32,
        bundleID: String?,
        isRunningOutput: Bool,
        isRunningInput: Bool,
        parentPID: Int32? = nil,
        responsiblePID: Int32? = nil,
        outputDeviceIDs: [UInt32] = []
    ) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.isRunningOutput = isRunningOutput
        self.isRunningInput = isRunningInput
        self.parentPID = parentPID
        self.responsiblePID = responsiblePID
        self.outputDeviceIDs = outputDeviceIDs
    }
}

/// A running app as the workspace reports it: only what grouping needs.
public struct RunningApp: Sendable, Hashable {
    public var pid: Int32
    public var bundleID: String?
    /// No user interface at all (a daemon like `avconferenced`): never shown as a row itself.
    public var isBackgroundOnly: Bool

    public init(pid: Int32, bundleID: String?, isBackgroundOnly: Bool = false) {
        self.pid = pid
        self.bundleID = bundleID
        self.isBackgroundOnly = isBackgroundOnly
    }
}

/// An app together with all of its audio processes.
public struct AudioApp: Sendable, Hashable, Identifiable {
    /// The app's bundle ID, or `pid:<n>` for the rare app without one. Settings are keyed by it.
    public var id: String
    public var bundleID: String?
    /// The app's own process IDs (more than one if several instances run).
    public var pids: [Int32]
    /// Core Audio process objects that belong to the app, helpers included, sorted.
    public var processObjectIDs: [UInt32]
    /// At least one of its processes has an active output stream.
    public var isPlaying: Bool
    /// At least one of its processes is using a microphone.
    public var isUsingMicrophone: Bool
    /// Output devices its processes play to, in order of appearance, without duplicates.
    public var outputDeviceIDs: [UInt32]

    public init(
        id: String,
        bundleID: String?,
        pids: [Int32],
        processObjectIDs: [UInt32],
        isPlaying: Bool,
        isUsingMicrophone: Bool,
        outputDeviceIDs: [UInt32] = []
    ) {
        self.id = id
        self.bundleID = bundleID
        self.pids = pids
        self.processObjectIDs = processObjectIDs
        self.isPlaying = isPlaying
        self.isUsingMicrophone = isUsingMicrophone
        self.outputDeviceIDs = outputDeviceIDs
    }
}
