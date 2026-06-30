import SwiftUI

struct PlaceholderTabScreen: View {
    let iconName: String
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer(minLength: AppSpacing.xl)

            ZStack {
                Circle()
                    .fill(Color.discoverSelectedGradient)
                    .frame(width: 82, height: 82)
                    .shadow(color: Color.brandPrimaryGlow.opacity(0.22), radius: 24, x: 0, y: 12)

                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.onAccentText)
            }

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(Font.App.screenTitle)
                    .foregroundStyle(Color.primaryText)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(Font.App.subtitle)
                    .foregroundStyle(Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppSpacing.xl)

            Spacer(minLength: AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, AppSpacing.lg)
        .discoverShellBackground()
    }
}

#Preview {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        PlaceholderTabScreen(
            iconName: "heart.fill",
            title: "tab.matches",
            subtitle: "placeholder.matches.subtitle"
        )
    }
}
