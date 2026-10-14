import SwiftUI

/// One app in the panel: icon and name, then its volume: a mute button showing the level and a
/// slider with the percentage.
struct AppRow: View {
    let app: AppRowState
    var onVolumeChange: @MainActor (Double) -> Void = { _ in }
    var onMuteChange: @MainActor (Bool) -> Void = { _ in }

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
            }
            HStack(spacing: 8) {
                MuteToggle(isMuted: app.isMuted, volume: app.volume, onChange: onMuteChange)
                    .frame(width: iconSize)
                Slider(value: Binding(get: { app.volume }, set: onVolumeChange), in: 0...1) {
                    Text("Volume")
                }
                .labelsHidden()
                .accessibilityValue(Text(percent))
                PercentLabel(text: percent)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(app.name))
    }

    private var percent: String {
        app.volume.formatted(.percent.precision(.fractionLength(0)))
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
                    Image(systemName: "speaker.wave.3.fill", variableValue: volume)
                }
            }
        }
        .toggleStyle(.button)
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .help(isMuted ? Text("Unmute") : Text("Mute"))
    }
}

/// The percentage, as wide as its widest value so the slider doesn't move while it changes.
private struct PercentLabel: View {
    let text: String

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(1.0.formatted(.percent.precision(.fractionLength(0))))
                .hidden()
            Text(text)
        }
        .font(.subheadline)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}
