import SwiftUI

enum AppTab: CaseIterable {
    case discover
    case matches
    case chats
    case plans
    case profile

    var title: LocalizedStringResource {
        switch self {
        case .discover:
            return "tab.discover"
        case .matches:
            return "tab.matches"
        case .chats:
            return "tab.chats"
        case .plans:
            return "tab.plans"
        case .profile:
            return "tab.profile"
        }
    }

    var icon: String {
        switch self {
        case .discover:
            return "safari"
        case .matches:
            return "heart"
        case .chats:
            return "bubble.left"
        case .plans:
            return "calendar"
        case .profile:
            return "person"
        }
    }

    var selectedIcon: String {
        switch self {
        case .discover:
            return "safari.fill"
        case .matches:
            return "heart.fill"
        case .chats:
            return "bubble.left.fill"
        case .plans:
            return "calendar"
        case .profile:
            return "person.fill"
        }
    }
}

struct AppTabBar: View {
    @Binding var selection: AppTab

    private let barCornerRadius: CGFloat = 26

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                AppTabBarItem(tab: tab, isSelected: selection == tab) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                        selection = tab
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .background {
            AppTabBarGlassBackground(cornerRadius: barCornerRadius)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

private struct AppTabBarGlassBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.65)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.discoverViolet.opacity(0.05),
                            Color.discoverPink.opacity(0.025),
                            Color.discoverVioletLight.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.glassBorderHighlight.opacity(0.28),
                            Color.discoverVioletLight.opacity(0.14),
                            Color.discoverPink.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        }
        .shadow(color: Color.discoverCardShadow.opacity(0.07), radius: 14, x: 0, y: 6)
        .shadow(color: Color.discoverViolet.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

private struct AppTabBarItem: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void
    @AppStorage("app.language") private var selectedLanguageRawValue = AppLanguage.system.rawValue

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.onAccentText : Color.primaryText.opacity(0.42))
                    .frame(width: 30, height: 30)
                    .background {
                        if isSelected {
                            Color.discoverSelectedGradient
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .shadow(color: Color.discoverViolet.opacity(0.26), radius: 8, x: 0, y: 3)
                        }
                    }

                Text(tab.title)
                    .font(Font.App.manrope(size: 9, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.discoverViolet : Color.secondaryText)
                    .tracking(-0.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .id(selectedLanguageRawValue)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            .spring(
                pressedScale: 0.92,
                response: 0.2,
                dampingFraction: 0.6
            )
        )
    }
}

#Preview {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        VStack {
            Spacer()
            AppTabBar(selection: .constant(.discover))
        }
    }
}

#Preview("Arabic RTL") {
    ZStack {
        Color.discoverBackgroundGradient.ignoresSafeArea()
        VStack {
            Spacer()
            AppTabBar(selection: .constant(.discover))
        }
    }
    .environment(\.locale, Locale(identifier: "ar"))
    .environment(\.layoutDirection, .rightToLeft)
}
