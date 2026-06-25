import SwiftUI

/// Tiled chat wallpaper using `ChatPattern` filled with the primary button gradient.
struct ChatPatternBackground: View {
    private enum UI {
        /// SVG viewBox width/height in `ChatPattern.svg`.
        static let sourceTileSize: CGFloat = 2250
        static let tileSize: CGFloat = 96
        static let patternOpacity: Double = 0.25

        static var tileScale: CGFloat { tileSize / sourceTileSize }
    }

    var body: some View {
        ZStack {
            Color.discoverBackgroundGradient

            GeometryReader { geometry in
                Color.brandPrimaryGradient
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

#Preview {
    ChatPatternBackground()
        .ignoresSafeArea()
}
