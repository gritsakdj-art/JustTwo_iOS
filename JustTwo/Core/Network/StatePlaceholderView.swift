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
                .font(Font.App.manrope(size: 22, weight: .bold))
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
        title: String(localized: "network.error.unauthorized"),
        subtitle: String(localized: "splash.error.unauthorized"),
        systemImage: NetworkError.unauthorized.systemImage,
        actionTitle: "auth.login",
        action: {}
    )
}

#Preview("TLS Failure") {
    StatePlaceholderView(
        title: String(localized: "network.error.tls_failure"),
        subtitle: String(localized: "splash.error.tls"),
        systemImage: NetworkError.tlsFailure.systemImage,
        actionTitle: "common.retry",
        action: {}
    )
}
