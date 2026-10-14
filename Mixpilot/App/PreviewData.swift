import AppKit

/// Sample rows with real app icons, for SwiftUI previews and snapshots.
enum PreviewData {
    static var apps: [AppRowState] {
        [
            row("com.apple.FaceTime", path: "/System/Applications/FaceTime.app"),
            row("com.apple.Music", path: "/System/Applications/Music.app"),
            row("com.apple.podcasts", path: "/System/Applications/Podcasts.app"),
            row("com.apple.Safari", path: "/Applications/Safari.app"),
        ]
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func row(_ id: String, path: String) -> AppRowState {
        // Some system apps in /Applications are symlinks; the target's icon has no alias badge.
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return AppRowState(
            id: id,
            name: FileManager.default.displayName(atPath: resolved),
            icon: NSWorkspace.shared.icon(forFile: resolved),
            isPlaying: true,
            isUsingMicrophone: false
        )
    }
}

extension MixerModel {
    static func preview(_ apps: [AppRowState] = PreviewData.apps) -> MixerModel {
        MixerModel(previewApps: apps)
    }
}
