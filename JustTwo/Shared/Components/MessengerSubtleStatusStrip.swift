import SwiftUI

struct MessengerSubtleStatusStrip: View {
    let text: String
    var showsSpinner = false

    var body: some View {
        HStack(spacing: 8) {
            if showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.secondaryText)
            }

            Text(text)
                .font(Font.App.manrope(size: 12, weight: .medium))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MessengerSubtleStatusStrip(text: "Refreshing…", showsSpinner: true)
        .background(Color.discoverBackgroundGradient)
}
