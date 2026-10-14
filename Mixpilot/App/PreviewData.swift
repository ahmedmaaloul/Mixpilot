import AppKit
import MixpilotCore

/// Sample rows with real app icons, for SwiftUI previews and snapshots.
enum PreviewData {
    static let devices = [
        OutputDevice(id: "BuiltInSpeakerDevice", objectID: 80, name: "MacBook Pro Speakers", kind: .macBookSpeakers),
        OutputDevice(id: "AirPods-UID", objectID: 81, name: "AirPods Pro", kind: .airPodsPro),
        OutputDevice(id: "Display-UID", objectID: 82, name: "Studio Display Speakers", kind: .displaySpeakers),
    ]

    static var apps: [AppRowState] {
        [
            row("com.apple.FaceTime", path: "/System/Applications/FaceTime.app",
                settings: AppAudioSettings(outputDeviceUID: "AirPods-UID", outputDeviceName: "AirPods Pro")),
            row("com.apple.Music", path: "/System/Applications/Music.app", settings: AppAudioSettings(volume: 0.35)),
            row("com.apple.podcasts", path: "/System/Applications/Podcasts.app",
                settings: AppAudioSettings(volume: 0.8, isMuted: true)),
            row("com.apple.Safari", path: "/Applications/Safari.app", settings: AppAudioSettings(volume: 0.6)),
        ]
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func row(_ id: String, path: String, settings: AppAudioSettings) -> AppRowState {
        // Some system apps in /Applications are symlinks; the target's icon has no alias badge.
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return AppRowState(
            id: id,
            name: FileManager.default.displayName(atPath: resolved),
            icon: NSWorkspace.shared.icon(forFile: resolved),
            isPlaying: true,
            isUsingMicrophone: false,
            settings: settings,
            ownOutputDeviceID: 80
        )
    }
}

extension MixerModel {
    static func preview(_ apps: [AppRowState] = PreviewData.apps) -> MixerModel {
        MixerModel(previewApps: apps, devices: PreviewData.devices)
    }
}
