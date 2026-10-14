import MixpilotAudio
import SwiftUI

/// Mixpilot: a menu bar app (no Dock icon, see `LSUIElement`) that sets the volume of each app.
@main
struct MixpilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// People decide whether the icon is in the menu bar (HIG). When it's hidden, opening Mixpilot
    /// again shows Settings.
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some Scene {
        // A window, not a menu: per-app sliders are too complex for a menu (HIG), the same choice
        // Control Center's Sound module makes. The system draws the panel's material and shape.
        MenuBarExtra(isInserted: $showInMenuBar) {
            MixerPanel(model: appDelegate.model)
        } label: {
            MenuBarIcon(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: appDelegate.model, loginItem: appDelegate.loginItem)
        }
    }
}

/// Owns the model so it exists from launch, before the panel is ever opened, and makes sure every
/// app gets its own sound back when Mixpilot quits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MixerModel()
    let loginItem = LoginItem()
    private let onboarding = OnboardingWindow()
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if SnapshotRenderer.runIfRequested() { return }
        #endif
        // What a previous run couldn't undo (Mixpilot's own taps vanish with its process).
        TapManager.removeLeftovers()
        MicrophoneController.restoreLeftovers()
        handleTerminationSignals()
        model.start()
        Shortcuts.install(model: model)
        #if DEBUG
        model.installDebugHooks()
        #endif
        if OnboardingWindow.isNeeded {
            onboarding.show(loginItem: loginItem)
        }
    }

    /// Opening Mixpilot while it runs (Finder, Spotlight, Launchpad) shows Settings: the way back
    /// when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        AppWindows.openSettings()
        return false
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
