import SwiftUI

struct OfflineSessionBanner: View {
    let connectivityState: SessionConnectivityState

    private var isValidating: Bool {
        connectivityState == .validationPending
    }

    private var title: LocalizedStringResource {
        isValidating ? "offline.banner.validating_title" : "offline.banner.title"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            iconBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Font.App.manrope(size: 15, weight: .bold))
                    .foregroundStyle(Color.primaryText)

                Text("offline.banner.subtitle")
                    .font(Font.App.manrope(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                .stroke(Color.warning.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color.discoverCardShadow.opacity(0.12), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text("offline.banner.subtitle"))
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
            .fill(Color.cardSurface)
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                    .fill(Color.warning.opacity(0.08))
            }
    }

    @ViewBuilder
    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(Color.warning.opacity(0.14))
                .frame(width: 36, height: 36)

            if isValidating {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.warning)
            } else {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.warning)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Offline Light") {
    OfflineSessionBanner(connectivityState: .offlineUsingCache)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .background(Color.discoverBackgroundGradient)
        .preferredColorScheme(.light)
}

#Preview("Offline Dark") {
    OfflineSessionBanner(connectivityState: .offlineUsingCache)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .background(Color.discoverBackgroundGradient)
        .preferredColorScheme(.dark)
}

#Preview("Validating") {
    OfflineSessionBanner(connectivityState: .validationPending)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .background(Color.discoverBackgroundGradient)
}
