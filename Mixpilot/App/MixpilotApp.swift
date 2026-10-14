import SwiftUI

/// Mixpilot: a menu bar app (no Dock icon, see `LSUIElement`) that sets the volume of each app.
@main
struct MixpilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A window, not a menu: per-app sliders are too complex for a menu (HIG), the same choice
        // Control Center's Sound module makes. The system draws the panel's material and shape.
        MenuBarExtra {
            MixerPanel(model: appDelegate.model)
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the model so it exists from launch, before the panel is ever opened.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MixerModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if SnapshotRenderer.runIfRequested() { return }
        #endif
        model.start()
    }
}
