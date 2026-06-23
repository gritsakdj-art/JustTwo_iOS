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
                    .font(Font.App.manrope(size: 16, weight: .bold))
                    .foregroundStyle(Color.primaryText)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(Font.App.subtitle)
                        .foregroundStyle(Color.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .frame(maxWidth: 360)
        .background(Color.cardSurface.opacity(0.88), in: RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.card, style: .continuous)
                .stroke(Color.hairline, lineWidth: 1)
        }
        .shadow(color: Color.discoverCardShadow.opacity(0.14), radius: 28, x: 0, y: 14)
        .padding(.horizontal, 24)
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
