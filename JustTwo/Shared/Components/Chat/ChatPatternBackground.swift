import SwiftUI

/// Tiled chat wallpaper using `ChatPattern` filled with a slowly drifting gradient.
struct ChatPatternBackground: View {
    private enum UI {
        /// SVG viewBox width/height in `ChatPattern.svg`.
        static let sourceTileSize: CGFloat = 2250
        static let tileSize: CGFloat = 192
        static let patternOpacity: Double = 0.2

        static var tileScale: CGFloat { tileSize / sourceTileSize }
    }

    var body: some View {
        ZStack {
            Color.discoverBackgroundGradient
                .scaleEffect(x: -1, y: -1)

            GeometryReader { geometry in
                FloatingPatternGradient()
                    .opacity(UI.patternOpacity)
                    .mask {
                        tiledPattern(in: geometry.size)
                    }
            }
        }
    }

    private func tiledPattern(in size: CGSize) -> some View {
        Image("ChatPattern")
            .renderingMode(.template)
            .resizable(resizingMode: .tile)
            .frame(
                width: size.width / UI.tileScale,
                height: size.height / UI.tileScale
            )
            .scaleEffect(UI.tileScale)
            .frame(width: size.width, height: size.height)
    }
}

/// Gradient whose axis slowly orbits the center while the center itself drifts
/// back and forth along the diagonal, so the pattern gently shimmers through the
/// pink-to-violet brand range instead of sitting still. Cheap to render: both
/// motions only recompute the gradient's two `UnitPoint`s per frame.
private struct FloatingPatternGradient: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds for one full revolution of the gradient axis. Slow on purpose:
    /// the wallpaper should feel alive, not animated.
    private static let revolutionDuration: TimeInterval = 18

    /// Seconds for one full back-and-forth diagonal drift of the gradient center.
    /// Deliberately not a multiple of `revolutionDuration`, so the combined motion
    /// doesn't visibly repeat on a short loop.
    private static let driftDuration: TimeInterval = 13

    /// How far the gradient center wanders from the middle (in unit space).
    private static let driftAmplitude: Double = 0.2

    private static let colors: [Color] = [
        .brandPrimaryGlow,
        .discoverPink,
        .discoverViolet,
        .discoverVioletLight
    ]

    var body: some View {
        if reduceMotion {
            gradient(angle: .pi * 0.75, drift: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let angle = time.truncatingRemainder(dividingBy: Self.revolutionDuration)
                    / Self.revolutionDuration * 2 * .pi
                let driftPhase = time.truncatingRemainder(dividingBy: Self.driftDuration)
                    / Self.driftDuration * 2 * .pi
                gradient(angle: angle, drift: sin(driftPhase) * Self.driftAmplitude)
            }
        }
    }

    private func gradient(angle: Double, drift: Double) -> LinearGradient {
        // The center slides along the top-leading/bottom-trailing diagonal.
        let centerX = 0.5 + drift
        let centerY = 0.5 + drift
        let dx = cos(angle) * 0.5
        let dy = sin(angle) * 0.5

        return LinearGradient(
            colors: Self.colors,
            startPoint: UnitPoint(x: centerX - dx, y: centerY - dy),
            endPoint: UnitPoint(x: centerX + dx, y: centerY + dy)
        )
    }
}

#Preview {
    ChatPatternBackground()
        .ignoresSafeArea()
}
