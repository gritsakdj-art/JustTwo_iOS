import SwiftUI

struct StatePlaceholderView: View {

    let title: String
    let subtitle: String
    let systemImage: String
    let actionTitle: LocalizedStringResource?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color.brandPrimary)

            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.discoverPrimaryText)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(Font.App.subtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.discoverSecondaryText)
                .padding(.horizontal, AppSpacing.xl)

            if let actionTitle, let action {
                PrimaryButton(actionTitle, action: action)
                    .padding(.horizontal, AppSpacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.discoverBackgroundGradient.ignoresSafeArea())
    }
}

#Preview("Unauthorized") {
    StatePlaceholderView(
        title: "Authorization required",
        subtitle: "Please sign in again.",
        systemImage: NetworkError.unauthorized.systemImage,
        actionTitle: "Sign in",
        action: {}
    )
}

#Preview("TLS Failure") {
    StatePlaceholderView(
        title: "Secure connection failed",
        subtitle: "VPN may be blocking the connection. Try disabling it.",
        systemImage: NetworkError.tlsFailure.systemImage,
        actionTitle: "Retry",
        action: {}
    )
}
