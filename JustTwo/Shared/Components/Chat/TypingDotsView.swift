import SwiftUI

struct TypingDotsView: View {
    var color: Color = .discoverViolet
    var dotSize: CGFloat = 4
    var spacing: CGFloat = 3

    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(isAnimating ? 1 : 0.5)
                    .opacity(isAnimating ? 1 : 0.35)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
        .onDisappear { isAnimating = false }
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        TypingDotsView()
        TypingDotsView(color: .brandPrimary, dotSize: 6, spacing: 4)
    }
    .padding()
    .background(Color.discoverBackgroundGradient)
}
