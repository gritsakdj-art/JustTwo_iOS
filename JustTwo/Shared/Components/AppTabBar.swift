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

    var body: some View {
        HStack {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Spacer()
                AppTabBarItem(tab: tab, isSelected: selection == tab) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                        selection = tab
                    }
                }
                Spacer()
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 30)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.discoverViolet.opacity(0.10))
                .frame(height: 0.5),
            alignment: .top
        )
    }
}

private struct AppTabBarItem: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.onAccentText : Color.discoverPrimaryText.opacity(0.45))
                    .frame(width: 36, height: 36)
                    .background {
                        if isSelected {
                            Color.discoverSelectedGradient
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: Color.discoverViolet.opacity(0.28), radius: 12, x: 0, y: 4)
                        }
                    }

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.discoverViolet : Color.discoverSecondaryText)
                    .tracking(-0.1)
            }
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
    AppTabBar(selection: .constant(.discover))
}

#Preview("Arabic RTL") {
    AppTabBar(selection: .constant(.discover))
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}
