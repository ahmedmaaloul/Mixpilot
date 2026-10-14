import MixpilotAudio
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

/// Owns the model so it exists from launch, before the panel is ever opened, and makes sure every
/// app gets its own sound back when Mixpilot quits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MixerModel()
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if SnapshotRenderer.runIfRequested() { return }
        #endif
        // Objects a previous run couldn't remove (Mixpilot's own taps vanish with its process).
        TapManager.removeLeftovers()
        handleTerminationSignals()
        model.start()
        #if DEBUG
        model.installDebugHooks()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopAudio()
    }

    /// `kill`, logout and Ctrl-C end the process without `applicationWillTerminate`; release the
    /// taps first so no app stays routed through a process that is going away.
    private func handleTerminationSignals() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [model] in
                model.stopAudio()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
