import SwiftUI

struct PlaceholderTabScreen: View {
    let iconName: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer(minLength: AppSpacing.xl)

            ZStack {
                Circle()
                    .fill(Color.discoverSelectedGradient)
                    .frame(width: 82, height: 82)
                    .shadow(color: Color.discoverViolet.opacity(0.24), radius: 24, x: 0, y: 12)

                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.onAccentText)
            }

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(Font.App.screenTitle)
                    .foregroundStyle(Color.discoverPrimaryText)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(Font.App.subtitle)
                    .foregroundStyle(Color.discoverSecondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppSpacing.xl)

            Spacer(minLength: AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, AppSpacing.lg)
    }
}

#Preview {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        PlaceholderTabScreen(
            iconName: "heart.fill",
            title: "Matches",
            subtitle: "People you liked and mutual matches will appear here."
        )
    }
}
