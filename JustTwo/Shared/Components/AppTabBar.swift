import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AppTab: String, CaseIterable, Hashable {
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

enum AppTabBarAppearance {
    static func configure() {
        #if canImport(UIKit)
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear

        let stacked = UITabBarItemAppearance()
        stacked.normal.iconColor = UIColor(Color.tabBarInactiveIcon)
        stacked.normal.titleTextAttributes = [
            .foregroundColor: UIColor(Color.tabBarInactiveTitle),
            .font: UIFont.systemFont(ofSize: 9, weight: .medium)
        ]
        stacked.selected.iconColor = UIColor(Color.discoverViolet)
        stacked.selected.titleTextAttributes = [
            .foregroundColor: UIColor(Color.discoverViolet),
            .font: UIFont.systemFont(ofSize: 9, weight: .bold)
        ]

        appearance.stackedLayoutAppearance = stacked
        appearance.inlineLayoutAppearance = stacked
        appearance.compactInlineLayoutAppearance = stacked

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().isTranslucent = true
        #endif
    }
}
