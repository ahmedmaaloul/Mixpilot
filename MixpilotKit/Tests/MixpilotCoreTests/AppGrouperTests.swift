import MixpilotCore
import Testing

@Suite("Grouping processes into apps")
struct AppGrouperTests {
    // Values taken from a real process list on macOS 27.
    let chrome = RunningApp(pid: 99492, bundleID: "com.google.Chrome")
    let mail = RunningApp(pid: 50757, bundleID: "com.apple.mail")
    let whatsApp = RunningApp(pid: 74986, bundleID: "net.whatsapp.WhatsApp")
    let mixpilot = RunningApp(pid: 500, bundleID: "app.mixpilot.mac")
    let controlCenter = RunningApp(pid: 887, bundleID: "com.apple.controlcenter")

    var apps: [RunningApp] { [chrome, mail, whatsApp, mixpilot, controlCenter] }

    @Test func appProcessBelongsToItself() {
        let result = AppGrouper.group(
            [AudioProcess(id: 112, pid: 99492, bundleID: "com.google.Chrome", isRunningOutput: true, isRunningInput: false)],
            runningApps: apps
        )
        #expect(result.map(\.id) == ["com.google.Chrome"])
        #expect(result.first?.isPlaying == true)
    }

    @Test func helpersAreFoldedIntoTheirAppByParent() {
        let result = AppGrouper.group(
            [
                AudioProcess(id: 112, pid: 99492, bundleID: "com.google.Chrome", isRunningOutput: false, isRunningInput: false),
                AudioProcess(id: 113, pid: 99646, bundleID: "com.google.Chrome.helper", isRunningOutput: true, isRunningInput: false, parentPID: 99492),
                AudioProcess(id: 114, pid: 99647, bundleID: "com.google.Chrome.helper", isRunningOutput: false, isRunningInput: true, parentPID: 99492),
            ],
            runningApps: apps
        )
        #expect(result.count == 1)
        #expect(result[0].processObjectIDs == [112, 113, 114])
        #expect(result[0].pids == [99492])
        #expect(result[0].isPlaying)
        #expect(result[0].isUsingMicrophone)
    }

    @Test func xpcServiceIsFoldedByResponsibleProcess() {
        // com.apple.WebKit.GPU is started by launchd (no parent) but Mail is responsible for it.
        let result = AppGrouper.group(
            [AudioProcess(id: 119, pid: 50765, bundleID: "com.apple.WebKit.GPU", isRunningOutput: true, isRunningInput: false, responsiblePID: 50757)],
            runningApps: apps
        )
        #expect(result.map(\.id) == ["com.apple.mail"])
    }

    @Test func extensionIsFoldedByBundleIDPrefix() {
        let result = AppGrouper.group(
            [AudioProcess(id: 124, pid: 53193, bundleID: "net.whatsapp.WhatsApp.ServiceExtension", isRunningOutput: true, isRunningInput: true)],
            runningApps: apps
        )
        #expect(result.map(\.id) == ["net.whatsapp.WhatsApp"])
    }

    @Test func prefixMustEndAtAComponentBoundary() {
        // "com.google.ChromeCast" must not be folded into "com.google.Chrome".
        let result = AppGrouper.group(
            [AudioProcess(id: 1, pid: 1234, bundleID: "com.google.ChromeCast", isRunningOutput: true, isRunningInput: false)],
            runningApps: apps
        )
        #expect(result.isEmpty)
    }

    @Test func longestBundleIDPrefixWins() {
        let outer = RunningApp(pid: 1, bundleID: "com.example")
        let inner = RunningApp(pid: 2, bundleID: "com.example.player")
        let result = AppGrouper.group(
            [AudioProcess(id: 9, pid: 99, bundleID: "com.example.player.helper", isRunningOutput: true, isRunningInput: false)],
            runningApps: [outer, inner]
        )
        #expect(result.map(\.id) == ["com.example.player"])
    }

    @Test func daemonsWithoutAnAppAreHidden() {
        let result = AppGrouper.group(
            [
                AudioProcess(id: 96, pid: 597, bundleID: "com.apple.mediaremoted", isRunningOutput: true, isRunningInput: false),
                AudioProcess(id: 126, pid: 75141, bundleID: "systemsoundserverd", isRunningOutput: true, isRunningInput: false),
            ],
            runningApps: apps
        )
        #expect(result.isEmpty)
    }

    @Test func mixpilotAndSystemAgentsAreHidden() {
        let result = AppGrouper.group(
            [
                AudioProcess(id: 98, pid: 887, bundleID: "com.apple.controlcenter", isRunningOutput: true, isRunningInput: false),
                AudioProcess(id: 200, pid: 500, bundleID: "app.mixpilot.mac", isRunningOutput: true, isRunningInput: false),
            ],
            runningApps: apps,
            hiddenPIDs: [500]
        )
        #expect(result.isEmpty)
    }

    @Test func ownProcessRuleWinsOverResponsibility() {
        // An app's own process must never be attributed to the app that launched it.
        let launcher = RunningApp(pid: 10, bundleID: "com.example.launcher")
        let game = RunningApp(pid: 11, bundleID: "com.example.game")
        let result = AppGrouper.group(
            [AudioProcess(id: 5, pid: 11, bundleID: "com.example.game", isRunningOutput: true, isRunningInput: false, parentPID: 10, responsiblePID: 10)],
            runningApps: [launcher, game]
        )
        #expect(result.map(\.id) == ["com.example.game"])
    }

    @Test func faceTimeCallAudioBelongsToFaceTime() {
        // avconferenced is listed as a (background-only) running app itself.
        let avconferenced = RunningApp(pid: 1037, bundleID: "com.apple.avconferenced", isBackgroundOnly: true)
        let faceTime = RunningApp(pid: 2000, bundleID: "com.apple.FaceTime")
        let call = AudioProcess(id: 102, pid: 1037, bundleID: "com.apple.avconferenced", isRunningOutput: true, isRunningInput: true)
        let result = AppGrouper.group([call], runningApps: [avconferenced, faceTime])
        #expect(result.map(\.id) == ["com.apple.FaceTime"])
        #expect(result.first?.isUsingMicrophone == true)
    }

    @Test func phoneCallAudioBelongsToPhoneWhenFaceTimeIsClosed() {
        let avconferenced = RunningApp(pid: 1037, bundleID: "com.apple.avconferenced", isBackgroundOnly: true)
        let phone = RunningApp(pid: 2001, bundleID: "com.apple.mobilephone")
        let call = AudioProcess(id: 102, pid: 1037, bundleID: "com.apple.avconferenced", isRunningOutput: true, isRunningInput: true)
        #expect(AppGrouper.group([call], runningApps: [avconferenced, phone]).map(\.id) == ["com.apple.mobilephone"])
    }

    @Test func callDaemonWithoutItsAppsIsHidden() {
        let avconferenced = RunningApp(pid: 1037, bundleID: "com.apple.avconferenced", isBackgroundOnly: true)
        let call = AudioProcess(id: 102, pid: 1037, bundleID: "com.apple.avconferenced", isRunningOutput: true, isRunningInput: false)
        #expect(AppGrouper.group([call], runningApps: [avconferenced]).isEmpty)
    }

    @Test func backgroundOnlyAppsAreHidden() {
        let daemon = RunningApp(pid: 50, bundleID: "com.example.daemon", isBackgroundOnly: true)
        let process = AudioProcess(id: 1, pid: 50, bundleID: "com.example.daemon", isRunningOutput: true, isRunningInput: false)
        #expect(AppGrouper.group([process], runningApps: [daemon]).isEmpty)
    }

    @Test func appWithoutBundleIDGetsAPIDIdentifier() {
        let tool = RunningApp(pid: 77, bundleID: nil)
        let result = AppGrouper.group(
            [AudioProcess(id: 3, pid: 77, bundleID: nil, isRunningOutput: true, isRunningInput: false)],
            runningApps: [tool]
        )
        #expect(result.map(\.id) == ["pid:77"])
    }
}

@Suite("Lingering rows")
struct LingerTests {
    @Test func inactiveItemStaysForTheDuration() {
        var linger = Linger<String>(duration: 3)
        #expect(linger.update(active: ["a"], now: 0) == ["a"])
        #expect(linger.update(active: [], now: 2.9) == ["a"])
        #expect(linger.update(active: [], now: 3.0) == [])
    }

    @Test func becomingActiveAgainResetsTheTimer() {
        var linger = Linger<String>(duration: 3)
        _ = linger.update(active: ["a"], now: 0)
        _ = linger.update(active: [], now: 1)
        _ = linger.update(active: ["a"], now: 2)
        #expect(linger.update(active: [], now: 4.5) == ["a"])
        #expect(linger.update(active: [], now: 5.0) == [])
    }

    @Test func nextExpiryIsTheEarliestLingeringItem() {
        var linger = Linger<String>(duration: 3)
        _ = linger.update(active: ["a", "b"], now: 0)
        _ = linger.update(active: ["b"], now: 1)
        // "a" was last active at 0, so it expires at 3; "b" is active and doesn't expire.
        #expect(linger.nextExpiry(active: ["b"]) == 3)
        #expect(linger.nextExpiry(active: ["a", "b"]) == nil)
    }
}
