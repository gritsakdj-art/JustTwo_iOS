import SwiftUI

/// Compact JustTwo spinner for inline image loading inside chat bubbles.
struct JustTwoImageLoadingIndicator: View {
    var size: CGFloat = 32
    var lineWidth: CGFloat = 3
    var accent: Color = .discoverViolet

    var body: some View {
        JustTwoSpinnerView(
            size: size,
            lineWidth: lineWidth,
            accent: accent,
            revolution: 0.85,
            arcFraction: 0.32,
            glowOpacity: 0.28,
            highlightOpacity: 0.18
        )
        .accessibilityLabel(Text("chats.imageBubble.loading"))
    }
}

#Preview {
    ZStack {
        Color.discoverMockLavender.opacity(0.4)
        JustTwoImageLoadingIndicator()
    }
    .frame(width: 180, height: 140)
}
