import SwiftUI

struct OfflineSessionBanner: View {
    let presentation: MessengerBannerPresentation

    private var title: String {
        String(localized: String.LocalizationValue(presentation.titleKey))
    }

    private var subtitle: String? {
        presentation.subtitleKey.map { String(localized: String.LocalizationValue($0)) }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            iconBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Font.App.manrope(size: 15, weight: .bold))
                    .foregroundStyle(Color.primaryText)

                if let subtitle {
                    Text(subtitle)
                        .font(Font.App.manrope(size: 13, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                .stroke(borderColor.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color.discoverCardShadow.opacity(0.12), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
    }

    private var borderColor: Color {
        switch presentation.style {
        case .refreshFailed:
            return Color.warning
        case .connectionRestoredRefreshing, .validating:
            return Color.discoverViolet
        case .offlineShowingCache:
            return Color.warning
        }
    }

    private var accentColor: Color {
        switch presentation.style {
        case .connectionRestoredRefreshing, .validating:
            return Color.discoverViolet
        case .offlineShowingCache, .refreshFailed:
            return Color.warning
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
            .fill(Color.cardSurface)
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                    .fill(accentColor.opacity(0.08))
            }
    }

    @ViewBuilder
    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.14))
                .frame(width: 36, height: 36)

            if presentation.showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .tint(accentColor)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accentColor)
            }
        }
        .accessibilityHidden(true)
    }

    private var iconName: String {
        switch presentation.style {
        case .validating, .connectionRestoredRefreshing:
            return "arrow.triangle.2.circlepath"
        case .offlineShowingCache:
            return "wifi.slash"
        case .refreshFailed:
            return "exclamationmark.triangle"
        }
    }
}

#Preview("Offline Light") {
    OfflineSessionBanner(presentation: .offlineShowingCache)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .background(Color.discoverBackgroundGradient)
        .preferredColorScheme(.light)
}

#Preview("Refreshing") {
    OfflineSessionBanner(presentation: .connectionRestoredRefreshing)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .background(Color.discoverBackgroundGradient)
}

#Preview("Refresh Failed") {
    OfflineSessionBanner(presentation: .refreshFailed)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .background(Color.discoverBackgroundGradient)
}
