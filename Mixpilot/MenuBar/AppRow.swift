import SwiftUI

/// One app in the panel: its icon and name. (Volume and output controls arrive in later
/// milestones.)
struct AppRow: View {
    let app: AppRowState
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24

    var body: some View {
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
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
