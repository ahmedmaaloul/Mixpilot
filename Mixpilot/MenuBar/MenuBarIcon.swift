import SwiftUI

/// The menu bar icon: a monochrome SF Symbol, which the menu bar renders as a template so it
/// adapts to light, dark and tinted menu bars and to the selected state.
struct MenuBarIcon: View {
    var body: some View {
        Image(systemName: "slider.vertical.3")
            .accessibilityLabel(Text(verbatim: "Mixpilot"))
    }
}
