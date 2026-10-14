import MixpilotAudio
import SwiftUI

/// The menu bar panel, laid out like a Control Center module: a header, the call mode switch,
/// one row per app that is playing sound, and the microphone.
///
/// The panel's background, corner radius and Liquid Glass come from the system's menu bar
/// window; nothing here paints a background.
struct MixerPanel: View {
    let model: MixerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader()
            CallModeSection(model: model)
            Divider()
                .padding(.horizontal, PanelMetrics.horizontalPadding)
            if model.needsAudioPermission {
                PermissionNotice()
            }
            if model.apps.isEmpty {
                NoAppsView()
            } else {
                AppList(model: model)
            }
            Divider()
                .padding(.horizontal, PanelMetrics.horizontalPadding)
            MicrophoneSection(model: model)
        }
        .frame(width: PanelMetrics.width)
        .animation(reduceMotion ? nil : .default, value: model.apps.map(\.id))
    }
}

/// Spacing shared by the panel's sections, matched to Control Center.
enum PanelMetrics {
    static let width: CGFloat = 320
    static let horizontalPadding: CGFloat = 14
}

private struct PanelHeader: View {
    var body: some View {
        HStack(alignment: .center) {
            Text(verbatim: "Mixpilot")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            MoreMenu()
        }
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

/// About and Quit, in a standard menu (action items are text only, as on macOS 27).
private struct MoreMenu: View {
    var body: some View {
        Menu {
            Button("About Mixpilot") {
                NSApp.activate()
                NSApp.orderFrontStandardAboutPanel(nil)
            }
            Divider()
            Button("Quit Mixpilot") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("More"))
    }
}

private struct AppList: View {
    let model: MixerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.apps) { app in
                    AppRow(
                        app: app,
                        devices: model.outputDevices,
                        defaultOutputUID: model.defaultOutputUID,
                        onVolumeChange: { model.setVolume($0, for: app.id) },
                        onMuteChange: { model.setMuted($0, for: app.id) },
                        onOutputChange: { model.setOutputDevice($0, for: app.id) }
                    )
                }
            }
            .padding(.horizontal, PanelMetrics.horizontalPadding)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        // As tall as the rows, up to about a dozen of them; scrolls beyond that.
        .frame(maxHeight: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Shown when macOS doesn't let Mixpilot hear apps. Apps keep playing normally meanwhile.
private struct PermissionNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To change the volume of apps, allow Mixpilot to record system audio.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") {
                // Privacy & Security ▸ Screen & System Audio Recording.
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .padding(.vertical, 6)
    }
}

/// A title, a short status line and a switch on the trailing edge, like the Wi-Fi and Bluetooth
/// menus. The switch carries the title for VoiceOver.
private struct SwitchRow: View {
    let title: Text
    @Binding var isOn: Bool
    let caption: Text

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                title
                    .font(.body)
                caption
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityHidden(true)
            Spacer(minLength: 8)
            Toggle(isOn: $isOn) { title }
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(caption)
        }
    }
}

/// Call mode: lowers every other app while a call goes on.
private struct CallModeSection: View {
    let model: MixerModel

    var body: some View {
        SwitchRow(
            title: Text("Call Mode"),
            isOn: Binding(get: { model.isCallModeActive }, set: { model.setCallMode($0) }),
            caption: caption
        )
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .padding(.vertical, 8)
    }

    private var caption: Text {
        if model.isCallModeActive && model.isCallDetected && !model.callAppNames.isEmpty {
            Text("On during your call in \(model.callAppNames.formatted(.list(type: .and))).")
        } else if model.isCallModeActive {
            Text("On until you turn it off.")
        } else {
            Text("Lowers other apps when a call starts.")
        }
    }
}

/// The microphone: on or off, its input volume and the apps using it.
private struct MicrophoneSection: View {
    let model: MixerModel
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24

    var body: some View {
        let microphone = model.microphone
        VStack(alignment: .leading, spacing: 6) {
            SwitchRow(
                title: Text("Microphone"),
                isOn: Binding(get: { !model.microphone.isMuted }, set: { model.setMicrophoneMuted(!$0) }),
                caption: microphoneCaption
            )
            .disabled(!microphone.canMute && !microphone.isMuted)

            if let volume = microphone.volume {
                HStack(spacing: 8) {
                    Image(systemName: microphone.isMuted ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: iconSize)
                        .accessibilityHidden(true)
                    Slider(value: Binding(get: { volume }, set: { model.setMicrophoneVolume($0) })) {
                        Text("Input Volume")
                    }
                    .labelsHidden()
                    .accessibilityValue(Text(volume.formatted(.percent.precision(.fractionLength(0)))))
                }
            }

            if !model.microphoneUserNames.isEmpty {
                Text("In use by \(model.microphoneUserNames.formatted(.list(type: .and))).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var microphoneCaption: Text {
        if model.microphone.isMuted {
            Text("Off for all apps.")
        } else if let name = model.microphone.deviceName {
            Text(name)
        } else {
            Text("No Microphone")
        }
    }
}

private struct NoAppsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Apps Playing Sound", systemImage: "speaker.slash")
        } description: {
            Text("Apps appear here when they play sound.")
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Previews

#Preview("Apps") {
    MixerPanel(model: .preview())
}

#Preview("Apps – Dark") {
    MixerPanel(model: .preview())
        .preferredColorScheme(.dark)
}

#Preview("Apps – German") {
    MixerPanel(model: .preview())
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Apps – German, Dark") {
    MixerPanel(model: .preview())
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}

#Preview("In a Call") {
    MixerPanel(model: PreviewData.inCall())
}

#Preview("In a Call – German, Dark") {
    MixerPanel(model: PreviewData.inCall())
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}

#Preview("Permission Needed") {
    MixerPanel(model: MixerModel(previewApps: PreviewData.apps, devices: PreviewData.devices, needsAudioPermission: true))
}

#Preview("No Apps") {
    MixerPanel(model: .preview([]))
}

#Preview("No Apps – German, Dark") {
    MixerPanel(model: .preview([]))
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}
