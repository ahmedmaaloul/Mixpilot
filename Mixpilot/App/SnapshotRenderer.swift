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
        // A menu bar agent isn't activated by macOS; as a regular app it is, and switches then draw
        // in their active (filled) look.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
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
        // Draw controls as in the active window (macOS won't let a process started from a terminal
        // become the active app), in the default blue accent rather than this Mac's, so pictures for
        // the website and README look like a fresh Mac.
        let hosting = NSHostingView(rootView: view
            .padding(.vertical, 6)
            .environment(\.controlActiveState, .key)
            .environment(\.routedTint, Color(nsColor: .systemBlue))
            .tint(Color(nsColor: .systemBlue)))
        let size = hosting.fittingSize
        // A key window on screen, captured by the window server, so controls look as they do in
        // use (switches and sliders filled with the accent color). `cacheDisplay` would draw them
        // inactive. A process may capture its own windows without the Screen Recording permission.
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let window = KeyWindow(
            contentRect: NSRect(x: screen.minX + 40, y: screen.minY + 40, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = false
        window.contentView = hosting
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Let SwiftUI and AppKit finish rendering (images, deferred layout, key appearance).
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        if let image = captureWindow(CGWindowID(window.windowNumber)) {
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
    }

    /// `CGWindowListCreateImage` is unavailable in the macOS 15+ SDK but still captures a process's
    /// own windows; looked up at runtime for this debug tool only.
    private static func captureWindow(_ windowID: CGWindowID) -> CGImage? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let createImage = unsafeBitCast(symbol, to: CreateImage.self)
        let includingWindow: UInt32 = 1 << 3
        let ignoreFramingAndBestResolution: UInt32 = (1 << 0) | (1 << 3)
        return createImage(.null, includingWindow, windowID, ignoreFramingAndBestResolution)?.takeRetainedValue()
    }

    private final class KeyWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }
}
#endif

