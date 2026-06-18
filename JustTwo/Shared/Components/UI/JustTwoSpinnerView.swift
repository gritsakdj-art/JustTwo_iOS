import SwiftUI

struct JustTwoSpinnerView: View {
    var size: CGFloat = 54
    var lineWidth: CGFloat = 5
    var accent: Color = .brandPrimary

    var revolution: TimeInterval = 0.9
    var arcFraction: CGFloat = 0.28
    var glowAngleShift: Double = -22
    var highlightAngleShift: Double = 10
    var glowOpacity: CGFloat = 0.34
    var highlightOpacity: CGFloat = 0.22

    var body: some View {
        let glowLineExtra = max(2, lineWidth * 0.75)
        let glowBlur = max(3, lineWidth * 1.4)
        let highlightWidth = max(1, lineWidth * 0.55)

        TimelineView(.animation) { context in
            let progress = (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: revolution)) / revolution
            let baseAngle = Angle.degrees(progress * 360)
            let glowAngle = baseAngle + .degrees(glowAngleShift)
            let highlightAngle = baseAngle + .degrees(highlightAngleShift)

            ZStack {
                Circle()
                    .strokeBorder(accent.opacity(0.18), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: arcFraction)
                    .stroke(
                        accent.opacity(glowOpacity),
                        style: StrokeStyle(
                            lineWidth: lineWidth + glowLineExtra,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .rotationEffect(glowAngle)
                    .blur(radius: glowBlur)
                    .blendMode(.plusLighter)

                Circle()
                    .trim(from: 0, to: arcFraction)
                    .stroke(
                        accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(baseAngle)

                Circle()
                    .trim(from: 0, to: arcFraction * 0.7)
                    .stroke(
                        Color.onAccentText.opacity(highlightOpacity),
                        style: StrokeStyle(lineWidth: highlightWidth, lineCap: .round)
                    )
                    .rotationEffect(highlightAngle)
                    .blur(radius: max(1, lineWidth * 0.25))
                    .blendMode(.screen)
            }
            .padding((lineWidth + glowLineExtra) / 2 + glowBlur * 0.8)
            .frame(width: size, height: size)
            .compositingGroup()
            .accessibilityLabel(Text("splash.loading.accessibility"))
        }
    }
}

#Preview {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        JustTwoSpinnerView()
    }
}
