import AppKit
import MixpilotAudio
import SwiftUI

/// Shows the welcome window the first time Mixpilot runs. An AppKit window hosting SwiftUI, so the
/// app delegate can open it at launch (a menu bar extra's label doesn't run SwiftUI tasks).
final class OnboardingWindow: NSObject, NSWindowDelegate {
    static let completedKey = "hasCompletedOnboarding"
    private var window: NSWindow?

    static var isNeeded: Bool {
        !UserDefaults.standard.bool(forKey: completedKey)
    }

    func show(loginItem: LoginItem) {
        if window == nil {
            let hosting = NSHostingView(rootView: OnboardingView(loginItem: loginItem) { [weak self] in
                self?.window?.close()
            })
            // A fixed size, measured once on the first (tallest) step. Letting SwiftUI resize the
            // window as it lays out loops on macOS 27 until AppKit throws.
            hosting.sizingOptions = []
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentView = hosting
            window.title = String(localized: "Welcome to Mixpilot")
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Closing the window, with Done or the close button, means "seen": it doesn't come back.
    /// The permission prompt still appears the first time an app's volume is changed.
    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        window = nil
    }
}


/// The first-launch window: what Mixpilot does, the System Audio Recording permission in plain
/// words, and Open at Login. Three short steps, each with one clear action.
struct OnboardingView: View {
    let loginItem: LoginItem
    /// Closes the window.
    var onDone: @MainActor () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = Step.welcome
    @State private var permission = PermissionState.unknown

    enum Step {
        case welcome, permission, done
    }

    enum PermissionState {
        case unknown, asking, granted, notGranted
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
            Group {
                switch step {
                case .welcome: welcome
                case .permission: permissionStep
                case .done: done
                }
            }
            .transition(.opacity)
        }
        .padding(.horizontal, 40)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(width: 480)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .default, value: step)
        .task {
            if await isGranted() {
                permission = .granted
            }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Welcome to Mixpilot")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Set the volume of each app, and keep your calls clear.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(
                    symbol: "speaker.wave.2",
                    title: Text("Volume for Each App"),
                    text: Text("Turn any app down, or send it to other speakers or headphones.")
                )
                FeatureRow(
                    symbol: "phone",
                    title: Text("Calls Come First"),
                    text: Text("When a call starts, other apps get quieter by themselves.")
                )
                FeatureRow(
                    symbol: "mic",
                    title: Text("Your Microphone at a Glance"),
                    text: Text("See which apps use it, and turn it off for all of them at once.")
                )
            }
            .padding(.vertical, 4)

            buttons {
                Button("Continue") {
                    step = permission == .granted ? .done : .permission
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var permissionStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Allow Access to App Sound")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("To change an app’s volume, Mixpilot needs the sound it plays. macOS calls this System Audio Recording. Sound is processed on your Mac and is never saved or sent.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            Group {
                switch permission {
                case .asking:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Answer the question from macOS.")
                            .foregroundStyle(.secondary)
                    }
                case .granted:
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                case .notGranted:
                    Text("You can allow it later in System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                case .unknown:
                    EmptyView()
                }
            }
            .font(.callout)
            .accessibilityElement(children: .combine)

            buttons {
                switch permission {
                case .unknown, .asking:
                    Button("Not Now") { step = .done }
                        .disabled(permission == .asking)
                    Button("Allow Access") { ask() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(permission == .asking)
                case .granted:
                    Button("Continue") { step = .done }
                        .keyboardShortcut(.defaultAction)
                case .notGranted:
                    Button("Open System Settings") { openAudioRecordingSettings() }
                    Button("Continue") { step = .done }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var done: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("You’re All Set")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Mixpilot is in the menu bar. Click \(Image(systemName: "slider.vertical.3")) to change the volume of each app. You can set keyboard shortcuts in Settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            Toggle("Open at Login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                .toggleStyle(.switch)

            buttons {
                Button("Done") {
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Helpers

    /// Buttons on the trailing edge, default action last, like a sheet.
    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer()
                content()
            }
            .padding(.top, 4)
        }
    }

    private func ask() {
        permission = .asking
        Task {
            let granted = await AudioPermission.request()
            permission = granted ? .granted : .notGranted
        }
    }

    private func isGranted() async -> Bool {
        await Task.detached { AudioPermission.isGranted() }.value
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: Text
    let text: Text
    @ScaledMetric(relativeTo: .title2) private var symbolWidth: CGFloat = 32

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: symbolWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.headline)
                text
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Welcome") {
    OnboardingView(loginItem: LoginItem())
}
