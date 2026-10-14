import MixpilotCore
import SwiftUI

/// One app in the panel: icon, name and output device, then its volume: a mute button showing
/// the level, a slider from 0 to 100 % (the app's own level), and the percentage.
struct AppRow: View {
    let app: AppRowState
    var devices: [OutputDevice] = []
    var defaultOutputUID: String?
    var onVolumeChange: @MainActor (Double) -> Void = { _ in }
    var onMuteChange: @MainActor (Bool) -> Void = { _ in }
    var onOutputChange: @MainActor (String?) -> Void = { _ in }

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)
                Text(app.name)
                    .font(.body)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                OutputMenu(
                    devices: devices,
                    settings: app.settings,
                    deviceInUse: deviceInUse,
                    onSelect: onOutputChange
                )
            }
            HStack(spacing: 8) {
                MuteToggle(isMuted: app.settings.isMuted, volume: app.settings.volume, onChange: onMuteChange)
                    .frame(width: iconSize)
                VolumeSlider(value: app.settings.volume, percent: percent, onChange: onVolumeChange)
                PercentLabel(text: percent)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(app.name))
    }

    private var percent: String {
        app.settings.volume.formatted(.percent.precision(.fractionLength(0)))
    }

    /// Where the app's sound comes out: the chosen device while connected, else the app's own
    /// device, else the system output.
    private var deviceInUse: OutputDevice? {
        if let chosen = app.settings.outputDeviceUID, let device = devices.first(where: { $0.id == chosen }) {
            return device
        }
        if let own = app.ownOutputDeviceID, let device = devices.first(where: { $0.objectID == own }) {
            return device
        }
        return devices.first { $0.id == defaultOutputUID }
    }
}

/// The volume slider: 0 % to 100 %, where 100 % is the app's own level.
private struct VolumeSlider: View {
    let value: Double
    let percent: String
    let onChange: @MainActor (Double) -> Void

    var body: some View {
        Slider(value: Binding(get: { value }, set: { onChange($0) }), in: AppAudioSettings.volumeRange) {
            Text("Volume")
        }
        .labelsHidden()
        .accessibilityValue(Text(percent))
        .accessibilityAdjustableAction { direction in
            // 5 % per step, like the system volume keys with Option and Shift.
            switch direction {
            case .increment: onChange(value + 0.05)
            case .decrement: onChange(value - 0.05)
            @unknown default: break
            }
        }
    }
}

/// The speaker symbol, filled to the current level, that mutes and unmutes the app.
private struct MuteToggle: View {
    let isMuted: Bool
    let volume: Double
    let onChange: @MainActor (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isMuted }, set: onChange)) {
            Label {
                Text("Mute")
            } icon: {
                if isMuted {
                    Image(systemName: "speaker.slash.fill")
                } else {
                    Image(systemName: "speaker.wave.3.fill", variableValue: min(volume, 1))
                }
            }
        }
        .toggleStyle(.button)
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .help(isMuted ? Text("Unmute") : Text("Mute"))
    }
}

/// Chooses the app's output device. The button shows the device in use; it takes the accent
/// color when the app was sent somewhere else than the system setting.
private struct OutputMenu: View {
    let devices: [OutputDevice]
    let settings: AppAudioSettings
    let deviceInUse: OutputDevice?
    let onSelect: @MainActor (String?) -> Void

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { settings.outputDeviceUID }, set: onSelect)) {
                Text("Use System Setting")
                    .tag(String?.none)
                Divider()
                ForEach(devices) { device in
                    Label(device.name, systemImage: device.kind.symbolName)
                        // macOS 27 hides menu images by default; devices keep theirs (HIG).
                        .labelStyle(.titleAndIcon)
                        .tag(Optional(device.id))
                }
                if let missing = disconnectedChoice {
                    Text("\(missing) (Not Connected)")
                        .tag(settings.outputDeviceUID)
                }
            } label: {
                Text("Output")
            }
            .pickerStyle(.inline)
        } label: {
            Label {
                Text("Output")
            } icon: {
                Image(systemName: deviceInUse?.kind.symbolName ?? "speaker.wave.2")
            }
            .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .tint(settings.outputDeviceUID == nil ? .secondary : .accentColor)
        .fixedSize()
        .accessibilityValue(Text(deviceInUse?.name ?? ""))
        .help(Text("Output: \(deviceInUse?.name ?? "")"))
    }

    /// The chosen device's name while it isn't connected.
    private var disconnectedChoice: String? {
        guard let uid = settings.outputDeviceUID, !devices.contains(where: { $0.id == uid }) else { return nil }
        return settings.outputDeviceName ?? uid
    }
}

/// The percentage, as wide as its widest value so the slider doesn't move while it changes.
private struct PercentLabel: View {
    let text: String

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(AppAudioSettings.volumeRange.upperBound.formatted(.percent.precision(.fractionLength(0))))
                .hidden()
            Text(text)
        }
        .font(.subheadline)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

extension OutputDevice.Kind {
    /// The SF Symbol Control Center and the Sound settings use for this kind of device.
    var symbolName: String {
        switch self {
        case .macBookSpeakers: "laptopcomputer"
        case .iMacSpeakers: "desktopcomputer"
        case .macMiniSpeakers: "macmini"
        case .macStudioSpeakers: "macstudio"
        case .displaySpeakers: "display"
        case .builtInSpeakers, .other: "speaker.wave.2"
        case .headphones, .bluetooth: "headphones"
        case .airPods: "airpods"
        case .airPodsPro: "airpods.pro"
        case .airPodsMax: "airpods.max"
        case .beats: "beats.headphones"
        case .tv: "tv"
        case .airPlay: "airplayaudio"
        case .homePod: "homepod"
        case .usb: "hifispeaker"
        case .virtual: "waveform"
        }
    }
}
