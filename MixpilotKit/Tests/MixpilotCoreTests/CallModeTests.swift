import MixpilotCore
import Testing

@Suite("Call detection")
struct CallModeTests {
    let whatsApp = "net.whatsapp.WhatsApp"
    let chrome = "com.google.Chrome"
    let voiceMemos = "com.apple.VoiceMemos"

    @Test func callStartsAfterTheStartDelay() {
        var mode = CallMode()
        mode.update(microphoneUsers: [whatsApp], now: 0)
        #expect(!mode.isActive)
        #expect(mode.nextDeadline() == 1)
        mode.update(microphoneUsers: [whatsApp], now: 1)
        #expect(mode.isActive)
        #expect(mode.callAppIDs == [whatsApp])
    }

    @Test func aQuickMicrophoneCheckIsNotACall() {
        var mode = CallMode()
        mode.update(microphoneUsers: [whatsApp], now: 0)
        mode.update(microphoneUsers: [], now: 0.5)
        mode.update(microphoneUsers: [], now: 2)
        #expect(!mode.isActive)
        #expect(mode.nextDeadline() == nil)
    }

    @Test func appsThatAreNotCallAppsDontCount() {
        var mode = CallMode()
        mode.update(microphoneUsers: [voiceMemos], now: 0)
        mode.update(microphoneUsers: [voiceMemos], now: 10)
        #expect(!mode.isActive)
    }

    @Test func aBrowserTabWithTheMicrophoneIsACall() {
        var mode = CallMode()
        mode.update(microphoneUsers: [chrome], now: 0)
        mode.update(microphoneUsers: [chrome], now: 1)
        #expect(mode.isActive)
    }

    @Test func callEndsAfterTheEndDelay() {
        var mode = startedCall()
        mode.update(microphoneUsers: [], now: 10)
        #expect(mode.isActive)
        #expect(mode.nextDeadline() == 15)
        mode.update(microphoneUsers: [], now: 14.9)
        #expect(mode.isActive)
        mode.update(microphoneUsers: [], now: 15)
        #expect(!mode.isActive)
        #expect(mode.callAppIDs.isEmpty)
    }

    @Test func aShortGapKeepsTheCall() {
        var mode = startedCall()
        mode.update(microphoneUsers: [], now: 10)
        mode.update(microphoneUsers: [whatsApp], now: 12)
        mode.update(microphoneUsers: [], now: 13)
        mode.update(microphoneUsers: [], now: 17.5)
        #expect(mode.isActive)
        mode.update(microphoneUsers: [], now: 18)
        #expect(!mode.isActive)
    }

    @Test func noDeadlineWhileTheCallIsOngoing() {
        let mode = startedCall()
        #expect(mode.nextDeadline() == nil)
    }

    @Test func switchingOffDuringACallWinsUntilTheCallEnds() {
        var mode = startedCall()
        mode.setManually(false)
        #expect(!mode.isActive)
        mode.update(microphoneUsers: [whatsApp], now: 20)
        #expect(!mode.isActive)
        // The call ends: automatic takes over again for the next call.
        mode.update(microphoneUsers: [], now: 21)
        mode.update(microphoneUsers: [], now: 26)
        #expect(mode.manualOverride == nil)
        mode.update(microphoneUsers: [whatsApp], now: 30)
        mode.update(microphoneUsers: [whatsApp], now: 31)
        #expect(mode.isActive)
    }

    @Test func switchingOnWithoutACallStaysOn() {
        var mode = CallMode()
        mode.setManually(true)
        #expect(mode.isActive)
        mode.update(microphoneUsers: [], now: 100)
        #expect(mode.isActive)
        mode.setManually(false)
        #expect(!mode.isActive)
    }

    @Test func switchedOnModeEndsWithTheNextCall() {
        var mode = CallMode()
        mode.setManually(true)
        mode.update(microphoneUsers: [whatsApp], now: 0)
        mode.update(microphoneUsers: [whatsApp], now: 1)
        #expect(mode.isActive)
        #expect(mode.manualOverride == nil)
        mode.update(microphoneUsers: [], now: 2)
        mode.update(microphoneUsers: [], now: 7)
        #expect(!mode.isActive)
    }

    @Test func withAutomaticOffOnlyTheSwitchCounts() {
        var mode = CallMode(configuration: .init(isAutomatic: false))
        mode.update(microphoneUsers: [whatsApp], now: 0)
        mode.update(microphoneUsers: [whatsApp], now: 5)
        #expect(mode.isCallDetected)
        #expect(!mode.isActive)
        mode.setManually(true)
        #expect(mode.isActive)
    }

    @Test func everyAppInTheCallIsRemembered() {
        var mode = startedCall()
        mode.update(microphoneUsers: [whatsApp, chrome], now: 12)
        #expect(mode.callAppIDs == [whatsApp, chrome])
    }

    private func startedCall() -> CallMode {
        var mode = CallMode()
        mode.update(microphoneUsers: [whatsApp], now: 0)
        mode.update(microphoneUsers: [whatsApp], now: 1)
        return mode
    }
}
