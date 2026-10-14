import MixpilotCore
import Testing

@Suite("Planning taps")
struct TapPlannerTests {
    func target(
        _ id: String = "com.spotify.client",
        gain: Double,
        playing: Bool = true,
        processes: [UInt32] = [10, 11],
        device: String = "BuiltInSpeakerDevice"
    ) -> TapTarget {
        TapTarget(appID: id, processObjectIDs: processes, gain: gain, isPlaying: playing, outputDeviceUID: device)
    }

    func session(
        gain: Double,
        running: Bool = true,
        processes: [UInt32] = [10, 11],
        device: String = "BuiltInSpeakerDevice",
        unitySince: Double? = nil
    ) -> TapSessionState {
        TapSessionState(processObjectIDs: processes, outputDeviceUID: device, gain: gain, isRunning: running, unitySince: unitySince)
    }

    @Test func appsAtFullVolumeAreNeverTapped() {
        #expect(TapPlanner.plan(targets: [target(gain: 1)], sessions: [:], now: 0).isEmpty)
    }

    @Test func changedVolumeCreatesASession() {
        let t = target(gain: 0.4)
        #expect(TapPlanner.plan(targets: [t], sessions: [:], now: 0) == [.create(t)])
    }

    @Test func mutedAppIsTapped() {
        let t = target(gain: 0)
        #expect(TapPlanner.plan(targets: [t], sessions: [:], now: 0) == [.create(t)])
    }

    @Test func blockedAppIsNotTapped() {
        #expect(TapPlanner.plan(targets: [target(gain: 0.4)], sessions: [:], now: 0, blocked: ["com.spotify.client"]).isEmpty)
    }

    @Test func gainChangeUpdatesTheRunningSession() {
        let actions = TapPlanner.plan(
            targets: [target(gain: 0.2)],
            sessions: ["com.spotify.client": session(gain: 0.4)],
            now: 0
        )
        #expect(actions == [.setGain(appID: "com.spotify.client", gain: 0.2)])
    }

    @Test func backAtFullVolumeKeepsTheSessionDuringTheGracePeriod() {
        let actions = TapPlanner.plan(
            targets: [target(gain: 1)],
            sessions: ["com.spotify.client": session(gain: 1, unitySince: 10)],
            now: 12
        )
        #expect(actions.isEmpty)
    }

    @Test func backAtFullVolumeRemovesTheSessionAfterTheGracePeriod() {
        let actions = TapPlanner.plan(
            targets: [target(gain: 1)],
            sessions: ["com.spotify.client": session(gain: 1, unitySince: 10)],
            now: 13
        )
        #expect(actions == [.destroy(appID: "com.spotify.client")])
    }

    @Test func firstMoveToFullVolumeSetsTheGain() {
        // The manager records unitySince when it applies this gain.
        let actions = TapPlanner.plan(
            targets: [target(gain: 1)],
            sessions: ["com.spotify.client": session(gain: 0.5)],
            now: 0
        )
        #expect(actions == [.setGain(appID: "com.spotify.client", gain: 1)])
    }

    @Test func quitAppIsRemoved() {
        let actions = TapPlanner.plan(targets: [], sessions: ["com.spotify.client": session(gain: 0.5)], now: 0)
        #expect(actions == [.destroy(appID: "com.spotify.client")])
    }

    @Test func newHelperProcessIsAddedToTheTap() {
        let actions = TapPlanner.plan(
            targets: [target(gain: 0.5, processes: [10, 11, 12])],
            sessions: ["com.spotify.client": session(gain: 0.5)],
            now: 0
        )
        #expect(actions == [.setProcesses(appID: "com.spotify.client", processObjectIDs: [10, 11, 12])])
    }

    @Test func audioStopsAndStartsWithTheApp() {
        let stop = TapPlanner.plan(
            targets: [target(gain: 0.5, playing: false)],
            sessions: ["com.spotify.client": session(gain: 0.5, running: true)],
            now: 0
        )
        #expect(stop == [.stop(appID: "com.spotify.client")])
        let start = TapPlanner.plan(
            targets: [target(gain: 0.5, playing: true)],
            sessions: ["com.spotify.client": session(gain: 0.5, running: false)],
            now: 0
        )
        #expect(start == [.start(appID: "com.spotify.client")])
    }

    @Test func deviceChangeMovesTheOutputAndKeepsTheTap() {
        let moved = target(gain: 0.5, device: "AirPods")
        let actions = TapPlanner.plan(
            targets: [moved],
            sessions: ["com.spotify.client": session(gain: 0.5)],
            now: 0
        )
        #expect(actions == [.setOutput(appID: "com.spotify.client", deviceUID: "AirPods")])
    }

    @Test func deviceChangeAndGainChangeTogether() {
        let actions = TapPlanner.plan(
            targets: [target(gain: 0.2, device: "AirPods")],
            sessions: ["com.spotify.client": session(gain: 0.5)],
            now: 0
        )
        #expect(actions == [
            .setOutput(appID: "com.spotify.client", deviceUID: "AirPods"),
            .setGain(appID: "com.spotify.client", gain: 0.2),
        ])
    }

    @Test func deviceChangeAtFullVolumeOnlyRemoves() {
        let actions = TapPlanner.plan(
            targets: [target(gain: 1, device: "AirPods")],
            sessions: ["com.spotify.client": session(gain: 1, unitySince: 0)],
            now: 1
        )
        #expect(actions == [.destroy(appID: "com.spotify.client")])
    }

    @Test func otherAppsAreUnaffected() {
        let music = target("com.apple.Music", gain: 0.3)
        let actions = TapPlanner.plan(
            targets: [target(gain: 0.5), music],
            sessions: ["com.spotify.client": session(gain: 0.5)],
            now: 0
        )
        #expect(actions == [.create(music)])
    }

    @Test func deadlineIsTheEarliestGraceEnd() {
        let sessions = [
            "a": session(gain: 1, unitySince: 5),
            "b": session(gain: 1, unitySince: 2),
            "c": session(gain: 0.5),
        ]
        #expect(TapPlanner.nextDeadline(sessions: sessions) == 5)
        #expect(TapPlanner.nextDeadline(sessions: ["c": session(gain: 0.5)]) == nil)
    }
}


@Suite("Planning taps: output devices")
struct TapRoutingTests {
    @Test func reroutedAppAtFullVolumeIsTapped() {
        let target = TapTarget(appID: "net.whatsapp.WhatsApp", processObjectIDs: [5], gain: 1, isPlaying: true,
                               outputDeviceUID: "AirPods", isRerouted: true)
        #expect(TapPlanner.plan(targets: [target], sessions: [:], now: 0) == [.create(target)])
    }

    @Test func reroutedSessionSurvivesTheGracePeriodAtFullVolume() {
        let target = TapTarget(appID: "net.whatsapp.WhatsApp", processObjectIDs: [5], gain: 1, isPlaying: true,
                               outputDeviceUID: "AirPods", isRerouted: true)
        let session = TapSessionState(processObjectIDs: [5], outputDeviceUID: "AirPods", gain: 1, isRunning: true, unitySince: 0)
        #expect(TapPlanner.plan(targets: [target], sessions: ["net.whatsapp.WhatsApp": session], now: 100).isEmpty)
    }
}
