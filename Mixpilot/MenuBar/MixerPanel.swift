import SwiftUI

/// The menu bar panel, laid out like a Control Center module: a header, then one row per app
/// that is playing sound.
///
/// The panel's background, corner radius and Liquid Glass come from the system's menu bar
/// window; nothing here paints a background.
struct MixerPanel: View {
    let model: MixerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader()
            if model.needsAudioPermission {
                PermissionNotice()
            }
            if model.apps.isEmpty {
                NoAppsView()
            } else {
                AppList(model: model)
            }
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
                        onVolumeChange: { model.setVolume($0, for: app.id) },
                        onMuteChange: { model.setMuted($0, for: app.id) }
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

#Preview("Permission Needed") {
    MixerPanel(model: MixerModel(previewApps: PreviewData.apps, needsAudioPermission: true))
}

#Preview("No Apps") {
    MixerPanel(model: .preview([]))
}

#Preview("No Apps – German, Dark") {
    MixerPanel(model: .preview([]))
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}
