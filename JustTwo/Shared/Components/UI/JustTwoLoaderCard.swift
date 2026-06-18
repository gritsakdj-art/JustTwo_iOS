import SwiftUI

struct JustTwoLoaderCard: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource?

    var spinnerSize: CGFloat = 58
    var lineWidth: CGFloat = 5

    var body: some View {
        VStack(spacing: 16) {
            JustTwoSpinnerView(
                size: spinnerSize,
                lineWidth: lineWidth,
                accent: .discoverViolet
            )

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.discoverPrimaryText)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(Font.App.subtitle)
                        .foregroundStyle(Color.discoverSecondaryText)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .frame(maxWidth: 360)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.discoverViolet.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: Color.discoverCardShadow.opacity(0.14), radius: 28, x: 0, y: 14)
        .padding(.horizontal, 24)
    }

    private var cardBackground: some ShapeStyle {
        Color.surface.opacity(0.88)
    }
}

#Preview {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        JustTwoLoaderCard(
            title: "splash.phase.loading_profile",
            subtitle: "splash.subtitle"
        )
    }
}
