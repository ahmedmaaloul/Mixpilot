import Foundation
import MixpilotCore
import Testing

/// Each test gets its own UserDefaults suite, removed afterwards.
private final class TemporaryDefaults {
    let name = "app.mixpilot.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

@Suite("Settings storage")
struct AppSettingsStoreTests {
    @Test func settingsSurviveARelaunch() {
        let temporary = TemporaryDefaults()
        let store = AppSettingsStore(defaults: temporary.defaults)
        store.set(AppAudioSettings(volume: 0.4, isMuted: true, outputDeviceUID: "AirPods-UID"), for: "com.spotify.client")

        let reopened = AppSettingsStore(defaults: temporary.defaults)
        #expect(reopened["com.spotify.client"] == AppAudioSettings(volume: 0.4, isMuted: true, outputDeviceUID: "AirPods-UID"))
    }

    @Test func unknownAppsAreUnchanged() {
        let temporary = TemporaryDefaults()
        let store = AppSettingsStore(defaults: temporary.defaults)
        #expect(store["com.apple.Music"] == .unchanged)
    }

    @Test func returningToUnchangedForgetsTheApp() {
        let temporary = TemporaryDefaults()
        let store = AppSettingsStore(defaults: temporary.defaults)
        store.set(AppAudioSettings(volume: 0.5), for: "com.apple.Music")
        store.set(.unchanged, for: "com.apple.Music")
        #expect(store.all.isEmpty)
        #expect(temporary.defaults.data(forKey: AppSettingsStore.defaultsKey) == nil)
    }

    @Test func appsWithoutBundleIDAreNotRemembered() {
        let temporary = TemporaryDefaults()
        let store = AppSettingsStore(defaults: temporary.defaults)
        store.set(AppAudioSettings(volume: 0.5), for: "pid:123")
        #expect(store.all.isEmpty)
    }

    @Test func removingOneAppKeepsTheOthers() {
        let temporary = TemporaryDefaults()
        let store = AppSettingsStore(defaults: temporary.defaults)
        store.set(AppAudioSettings(volume: 0.5), for: "a")
        store.set(AppAudioSettings(volume: 0.7), for: "b")
        store.remove("a")
        #expect(AppSettingsStore(defaults: temporary.defaults).all == ["b": AppAudioSettings(volume: 0.7)])
    }

    @Test func removeAllForgetsEverything() {
        let temporary = TemporaryDefaults()
        let store = AppSettingsStore(defaults: temporary.defaults)
        store.set(AppAudioSettings(volume: 0.5), for: "a")
        store.removeAll()
        #expect(AppSettingsStore(defaults: temporary.defaults).all.isEmpty)
    }

    @Test func corruptDataIsIgnored() {
        let temporary = TemporaryDefaults()
        temporary.defaults.set(Data("not json".utf8), forKey: AppSettingsStore.defaultsKey)
        #expect(AppSettingsStore(defaults: temporary.defaults).all.isEmpty)
    }

    @Test func invalidValuesAreRepairedWhenLoading() throws {
        let temporary = TemporaryDefaults()
        let json = """
        {
          "too.loud": {"volume": 1.6, "isMuted": false},
          "negative": {"volume": -1},
          "only.muted": {"isMuted": true, "futureField": 42},
          "empty.device": {"volume": 0.5, "outputDeviceUID": ""},
          "pid:7": {"volume": 0.5},
          "unchanged": {"volume": 1}
        }
        """
        temporary.defaults.set(Data(json.utf8), forKey: AppSettingsStore.defaultsKey)
        let store = AppSettingsStore(defaults: temporary.defaults)
        // Boosted values from early builds come back at 100 %.
        #expect(store.all["too.loud"] == nil)
        #expect(store["negative"].volume == 0)
        #expect(store["only.muted"] == AppAudioSettings(volume: 1, isMuted: true))
        #expect(store["empty.device"].outputDeviceUID == nil)
        #expect(store.all["pid:7"] == nil)
        #expect(store.all["unchanged"] == nil)
    }

    @Test func storesAreIndependentPerKey() {
        let temporary = TemporaryDefaults()
        let first = AppSettingsStore(defaults: temporary.defaults, key: "one")
        first.set(AppAudioSettings(volume: 0.3), for: "a")
        #expect(AppSettingsStore(defaults: temporary.defaults, key: "two").all.isEmpty)
    }
}

@Suite("App audio settings")
struct AppAudioSettingsTests {
    @Test func gainFollowsMute() {
        #expect(AppAudioSettings(volume: 0.7).gain == 0.7)
        #expect(AppAudioSettings(volume: 0.5, isMuted: true).gain == 0)
        #expect(AppAudioSettings.unchanged.gain == 1)
    }

    @Test func volumeIsClamped() {
        #expect(AppAudioSettings(volume: 3).volume == 1)
        #expect(AppAudioSettings(volume: -0.5).volume == 0)
        #expect(AppAudioSettings(volume: .nan).volume == 1)
        var settings = AppAudioSettings()
        settings.volume = 5
        #expect(settings.volume == 1)
    }

    @Test func neverLouderThanTheAppItself() {
        #expect(AppAudioSettings.volumeRange.upperBound == 1)
        #expect(AppAudioSettings(volume: 1.5).gain == 1)
    }

    @Test func aChosenDeviceIsAChange() {
        #expect(!AppAudioSettings(outputDeviceUID: "AirPods").isUnchanged)
    }
}

@Suite("Output device kinds")
struct OutputDeviceKindTests {
    typealias T = OutputDevice.Transport

    @Test func builtInSpeakersFollowTheMacModel() {
        #expect(OutputDevice.Kind.classify(transport: T.builtIn, name: "MacBook Pro Speakers") == .macBookSpeakers)
        #expect(OutputDevice.Kind.classify(transport: T.builtIn, name: "MacBook Air-Lautsprecher") == .macBookSpeakers)
        #expect(OutputDevice.Kind.classify(transport: T.builtIn, name: "iMac Speakers") == .iMacSpeakers)
        #expect(OutputDevice.Kind.classify(transport: T.builtIn, name: "Mac mini Speakers") == .macMiniSpeakers)
        #expect(OutputDevice.Kind.classify(transport: T.builtIn, name: "Speakers") == .builtInSpeakers)
        #expect(OutputDevice.Kind.classify(transport: T.builtIn, name: "External Headphones", isHeadphoneJack: true) == .headphones)
    }

    @Test func bluetoothHeadphones() {
        #expect(OutputDevice.Kind.classify(transport: T.bluetooth, name: "Ahmed’s AirPods Pro") == .airPodsPro)
        #expect(OutputDevice.Kind.classify(transport: T.bluetooth, name: "AirPods Max") == .airPodsMax)
        #expect(OutputDevice.Kind.classify(transport: T.bluetooth, name: "AirPods") == .airPods)
        #expect(OutputDevice.Kind.classify(transport: T.bluetoothLE, name: "Beats Studio Buds") == .beats)
        #expect(OutputDevice.Kind.classify(transport: T.bluetooth, name: "WH-1000XM5") == .bluetooth)
    }

    @Test func otherTransports() {
        #expect(OutputDevice.Kind.classify(transport: T.hdmi, name: "LG TV") == .tv)
        #expect(OutputDevice.Kind.classify(transport: T.displayPort, name: "Studio Display Speakers") == .displaySpeakers)
        #expect(OutputDevice.Kind.classify(transport: T.airPlay, name: "Living Room HomePod") == .homePod)
        #expect(OutputDevice.Kind.classify(transport: T.airPlay, name: "Apple TV") == .airPlay)
        #expect(OutputDevice.Kind.classify(transport: T.usb, name: "Scarlett 2i2") == .usb)
        #expect(OutputDevice.Kind.classify(transport: T.virtual, name: "Microsoft Teams Audio") == .virtual)
        #expect(OutputDevice.Kind.classify(transport: 0, name: "Mystery") == .other)
    }
}

@Suite("Call mode settings storage")
struct CallModeSettingsTests {
    @Test func defaultsWhenNothingIsStored() {
        let temporary = TemporaryDefaults()
        let settings = CallModeSettings.load(from: temporary.defaults)
        #expect(settings.isAutomatic)
        #expect(settings.level == 0.2)
        #expect(settings.callApps == KnownCallApps.all)
    }

    @Test func settingsSurviveARelaunch() {
        let temporary = TemporaryDefaults()
        CallModeSettings(isAutomatic: false, level: 0.35, excludedApps: ["com.google.Chrome"]).save(to: temporary.defaults)
        let loaded = CallModeSettings.load(from: temporary.defaults)
        #expect(!loaded.isAutomatic)
        #expect(loaded.level == 0.35)
        #expect(!loaded.callApps.contains("com.google.Chrome"))
        #expect(loaded.callApps.contains("net.whatsapp.WhatsApp"))
    }

    @Test func defaultSettingsAreNotStored() {
        let temporary = TemporaryDefaults()
        CallModeSettings(level: 0.5).save(to: temporary.defaults)
        CallModeSettings().save(to: temporary.defaults)
        #expect(temporary.defaults.data(forKey: CallModeSettings.defaultsKey) == nil)
    }

    @Test func levelIsClamped() {
        #expect(CallModeSettings(level: 3).level == 1)
        #expect(CallModeSettings(level: -1).level == 0)
        var settings = CallModeSettings()
        settings.level = .nan
        #expect(settings.level == 0.2)
    }

    @Test func corruptOrPartialDataFallsBackToDefaults() {
        let temporary = TemporaryDefaults()
        temporary.defaults.set(Data("{".utf8), forKey: CallModeSettings.defaultsKey)
        #expect(CallModeSettings.load(from: temporary.defaults) == CallModeSettings())
        temporary.defaults.set(Data(#"{"level": 7}"#.utf8), forKey: CallModeSettings.defaultsKey)
        let partial = CallModeSettings.load(from: temporary.defaults)
        #expect(partial.level == 1)
        #expect(partial.isAutomatic)
    }
}
