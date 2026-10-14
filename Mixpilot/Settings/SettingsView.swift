import KeyboardShortcuts
import MixpilotAudio
import MixpilotCore
import SwiftUI

/// Mixpilot ▸ Settings… (⌘,): toolbar panes with grouped forms. Every change applies at once.
struct SettingsView: View {
    let model: MixerModel
    let loginItem: LoginItem
    /// Reopens on the pane used last (HIG).
    @AppStorage("settingsPane") private var pane = Pane.general

    enum Pane: String {
        case general, calls, apps, shortcuts
    }

    var body: some View {
        TabView(selection: $pane) {
            GeneralPane(loginItem: loginItem)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Pane.general)
            CallsPane(model: model)
                .tabItem { Label("Calls", systemImage: "phone") }
                .tag(Pane.calls)
            AppsPane(model: model)
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
                .tag(Pane.apps)
            ShortcutsPane()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(Pane.shortcuts)
        }
        .frame(width: 500)
    }
}

// MARK: - General

private struct GeneralPane: View {
    let loginItem: LoginItem
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @State private var hasAudioPermission: Bool?

    var body: some View {
        Form {
            Section {
                Toggle("Open at Login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                if loginItem.needsApproval {
                    LabeledContent {
                        Button("Open System Settings") { loginItem.openSystemSettings() }
                    } label: {
                        Text("Allow Mixpilot under Login Items in System Settings.")
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $showInMenuBar) {
                    Text("Show in Menu Bar")
                    Text("When it’s hidden, open Mixpilot again to see these settings. Your shortcuts keep working.")
                }
            }

            Section {
                LabeledContent {
                    switch hasAudioPermission {
                    case .some(true):
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    case .some(false):
                        Button("Open System Settings") { openAudioRecordingSettings() }
                    case .none:
                        ProgressView()
                            .controlSize(.small)
                    }
                } label: {
                    Text("System Audio Recording")
                    Text("Needed to change the volume of apps. Sound is processed on your Mac and is never saved or sent.")
                }
            } header: {
                Text("Permissions")
            }

            Section {
                LabeledContent("Version") {
                    Text(verbatim: AppInfo.version)
                }
                Button("About Mixpilot") { AppWindows.showAbout() }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
        .task {
            // The check creates a short-lived tap: keep it off the main thread.
            hasAudioPermission = await Task.detached { AudioPermission.isGranted() }.value
        }
    }
}

/// Privacy & Security ▸ Screen & System Audio Recording.
func openAudioRecordingSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
        NSWorkspace.shared.open(url)
    }
}

enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

// MARK: - Calls

private struct CallsPane: View {
    let model: MixerModel

    var body: some View {
        let settings = model.callModeSettings
        Form {
            Section {
                Toggle(isOn: binding(\.isAutomatic)) {
                    Text("Lower Other Apps During Calls")
                    Text("Call mode turns on by itself when a call app uses the microphone. You can always turn it on or off in the menu bar.")
                }
                LabeledContent {
                    HStack {
                        Slider(value: binding(\.level), in: 0...1) {
                            Text("Volume of Other Apps")
                        }
                        .labelsHidden()
                        .accessibilityValue(Text(settings.level.formatted(.percent.precision(.fractionLength(0)))))
                        Text(settings.level.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(width: 200)
                } label: {
                    Text("Volume of Other Apps")
                    Text("Their own volume stays as you set it.")
                }
            }

            Section {
                ForEach(installedCallApps, id: \.self) { bundleID in
                    let identity = AppDirectory().identity(forBundleID: bundleID)
                    Toggle(isOn: Binding(
                        get: { !settings.excludedApps.contains(bundleID) },
                        set: { included in
                            var updated = settings
                            if included {
                                updated.excludedApps.remove(bundleID)
                            } else {
                                updated.excludedApps.insert(bundleID)
                            }
                            model.setCallModeSettings(updated)
                        }
                    )) {
                        Label {
                            Text(identity.name)
                        } icon: {
                            Image(nsImage: identity.icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                    }
                }
            } header: {
                Text("Detect Calls In")
            } footer: {
                Text("Browsers count when a website uses the microphone, as in a video call.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Known call apps and browsers that are installed, call apps first.
    private var installedCallApps: [String] {
        (KnownCallApps.callApps + KnownCallApps.browsers).filter(AppDirectory.isInstalled)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CallModeSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.callModeSettings[keyPath: keyPath] },
            set: { value in
                var updated = model.callModeSettings
                updated[keyPath: keyPath] = value
                model.setCallModeSettings(updated)
            }
        )
    }
}

// MARK: - Apps

private struct AppsPane: View {
    let model: MixerModel
    @State private var isConfirmingForgetAll = false

    var body: some View {
        Group {
            if model.rememberedApps.isEmpty {
                ContentUnavailableView {
                    Label("No Remembered Apps", systemImage: "square.grid.2x2")
                } description: {
                    Text("When you change an app’s volume or output, Mixpilot remembers it and uses it again the next time the app plays sound.")
                }
                .frame(height: 280)
            } else {
                Form {
                    Section {
                        ForEach(model.rememberedApps) { app in
                            LabeledContent {
                                Button("Forget") { model.forget(app.id) }
                                    .accessibilityLabel(Text("Forget \(app.name)"))
                            } label: {
                                Label {
                                    Text(app.name)
                                    Text(summary(of: app.settings))
                                } icon: {
                                    Image(nsImage: app.icon)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }
                            }
                        }
                    } footer: {
                        HStack {
                            Text("Mixpilot uses these settings whenever the app plays sound.")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Forget All…") { isConfirmingForgetAll = true }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .confirmationDialog("Forget All Apps?", isPresented: $isConfirmingForgetAll) {
            Button("Forget All", role: .destructive) { model.forgetAll() }
        } message: {
            Text("Every app plays at its own volume and on its own output again.")
        }
    }

    /// "35 %, Muted, AirPods Pro", in the person's language.
    private func summary(of settings: AppAudioSettings) -> String {
        var parts = [settings.volume.formatted(.percent.precision(.fractionLength(0)))]
        if settings.isMuted {
            parts.append(String(localized: "Muted"))
        }
        if settings.outputDeviceUID != nil {
            parts.append(settings.outputDeviceName ?? String(localized: "Other Output"))
        }
        return parts.formatted(.list(type: .and, width: .narrow))
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    var body: some View {
        Form {
            Section {
                recorder(Text("Turn Microphone On or Off"), for: .toggleMicrophone)
                recorder(Text("Turn Call Mode On or Off"), for: .toggleCallMode)
            }
            Section {
                recorder(Text("Turn Up the App in Front"), for: .raiseFrontmostApp)
                recorder(Text("Turn Down the App in Front"), for: .lowerFrontmostApp)
            } footer: {
                Text("Changes the volume of the app you’re using in steps of 10 %, up to its own level. Shortcuts work in every app.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func recorder(_ title: Text, for name: KeyboardShortcuts.Name) -> some View {
        LabeledContent {
            KeyboardShortcuts.Recorder(for: name)
                // The recorder is a search field underneath; say what it sets.
                .accessibilityLabel(title)
        } label: {
            title
        }
    }
}

// MARK: - Previews

#Preview("Settings") {
    SettingsView(model: .preview(), loginItem: LoginItem())
}
