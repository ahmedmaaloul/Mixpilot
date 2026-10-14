import MixpilotAudio
import SwiftUI

/// The menu bar icon: a monochrome SF Symbol, which the menu bar renders as a template so it
/// adapts to light, dark and tinted menu bars and to the selected state. It shows when the
/// microphone is off and when call mode is on, so neither is ever invisible.
struct MenuBarIcon: View {
    let model: MixerModel

    var body: some View {
        if model.microphone.isMuted {
            Image(systemName: "mic.slash")
                .accessibilityLabel(Text("Mixpilot, Microphone Off"))
        } else if model.isCallModeActive {
            Image(systemName: "phone")
                .accessibilityLabel(Text("Mixpilot, Call Mode On"))
        } else {
            Image(systemName: "slider.vertical.3")
                .accessibilityLabel(Text(verbatim: "Mixpilot"))
        }
    }
}
