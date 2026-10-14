#if DEBUG
import AppKit
import SwiftUI

/// Renders the preview catalog to PNG files for design review, then quits (debug builds only):
///
///     Mixpilot.app/Contents/MacOS/Mixpilot -MixpilotSnapshots <folder> [-AppleLanguages "(de)"]
///
/// `scripts/snapshots.sh` runs it for English and German. Each view is drawn in light and dark
/// appearance on the window background color, which is how the panel looks with Reduce
/// Transparency; the live panel adds the system's translucent material.
enum SnapshotRenderer {
    /// The views to render, by file name.
    @MainActor
    static var catalog: [(name: String, view: AnyView)] {
        [
            ("panel-apps", AnyView(MixerPanel(model: .preview()))),
            ("panel-empty", AnyView(MixerPanel(model: .preview([])))),
            ("panel-call", AnyView(MixerPanel(model: PreviewData.inCall()))),
            ("onboarding", AnyView(OnboardingView(loginItem: LoginItem()))),
            ("settings", AnyView(SettingsView(model: .preview(), loginItem: LoginItem()))),
            ("panel-permission", AnyView(MixerPanel(model: MixerModel(previewApps: PreviewData.apps, needsAudioPermission: true)))),
        ]
    }

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-MixpilotSnapshots")
    }

    /// Renders and quits if the launch arguments ask for it; returns false otherwise.
    @MainActor
    static func runIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-MixpilotSnapshots"), index + 1 < arguments.count else {
            return false
        }
        let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let language = Bundle.main.preferredLocalizations.first ?? "en"

        for (name, view) in catalog {
            for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                let url = folder.appendingPathComponent("\(name)-\(language)-\(suffix).png")
                render(view, appearance: appearance, to: url)
            }
        }
        NSApp.terminate(nil)
        return true
    }

    @MainActor
    private static func render(_ view: AnyView, appearance: NSAppearance.Name, to url: URL) {
        let hosting = NSHostingView(rootView: view.padding(.vertical, 6))
        let size = hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI finish its first render pass (images, deferred layout).
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        // Draw the background first so the PNG isn't transparent.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        window.appearance?.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            hosting.bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif

