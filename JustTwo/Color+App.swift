import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - JustTwo Design System

extension Color {
    // MARK: Base — Optimized for Cozy & Modern Dating

    private static let lightSurface = Color(hex: "#FFFDFB") // Чуть теплее, комфортнее для глаз
    private static let darkSurface = Color(hex: "#0B0813")  // Глубже, чтобы фотки пользователей «горели»

    private static let lightOnAccentText = Color(hex: "#FFFFFF")
    private static let darkOnAccentText = Color(hex: "#FFFFFF")

    private static let lightBrandPrimary = Color(hex: "#D82C5F") // Сочный ягодный без грязного подтона
    private static let darkBrandPrimary = Color(hex: "#E6396E")

    private static let lightBrandPrimaryPressed = Color(hex: "#A61B43")
    private static let darkBrandPrimaryPressed = Color(hex: "#C22552")

    private static let lightBrandGradientEnd = Color(hex: "#6344E3") // Благородный фиолетовый для мэтчей
    private static let darkBrandGradientEnd = Color(hex: "#7956FA")

    private static let lightIndigo = Color(hex: "#4F46E5")
    private static let darkIndigo = Color(hex: "#818CF8")

    private static let lightBrandPrimaryGlow = Color(hex: "#FF7597")
    private static let darkBrandPrimaryGlow = Color(hex: "#FF5F87")

    // MARK: Discover — Backgrounds (Смягчили градиент, убирая визуальный шум)

    private static let lightDiscoverBackgroundTop = Color(hex: "#FFFDFB")
    private static let darkDiscoverBackgroundTop = Color(hex: "#0B0813")

    private static let lightDiscoverBackgroundMiddle = Color(hex: "#FFF0F2") // Мягкий пастельный вместо едкого розового
    private static let darkDiscoverBackgroundMiddle = Color(hex: "#160F24")

    private static let lightDiscoverBackgroundBottom = Color(hex: "#F6F0FF")
    private static let darkDiscoverBackgroundBottom = Color(hex: "#0A0E1A")

    private static let lightDiscoverPrimaryText = Color(hex: "#1F0F18")
    private static let darkDiscoverPrimaryText = Color(hex: "#FFF5FA")

    private static let lightDiscoverSecondaryText = Color(hex: "#7A6570")
    private static let darkDiscoverSecondaryText = Color(hex: "#A89AA4") // Чистый серебристый оттенок в темноте

    private static let lightDiscoverViolet = Color(hex: "#6344E3")
    private static let darkDiscoverViolet = Color(hex: "#7956FA")

    private static let lightDiscoverVioletLight = Color(hex: "#8265F0")
    private static let darkDiscoverVioletLight = Color(hex: "#9F87FF")

    private static let lightDiscoverPink = Color(hex: "#D82C5F")
    private static let darkDiscoverPink = Color(hex: "#E6396E")

    private static let lightDiscoverPinkLight = Color(hex: "#E0537E")
    private static let darkDiscoverPinkLight = Color(hex: "#ED6B90")

    private static let lightDiscoverCardShadow = Color(hex: "#2C121C").opacity(0.12) // Честная альфа для теней карточек
    private static let darkDiscoverCardShadow = Color(hex: "#000000").opacity(0.5)

    private static let lightDiscoverMockLavender = Color(hex: "#F3EDFF")
    private static let darkDiscoverMockLavender = Color(hex: "#251D36")

    private static let lightDiscoverMockPeach = Color(hex: "#FFEBE5")
    private static let darkDiscoverMockPeach = Color(hex: "#361B22")

    private static let lightDiscoverOnline = Color(hex: "#10D37F")
    private static let darkDiscoverOnline = Color(hex: "#2CE491")

    private static let lightDiscoverCardScrim = Color(hex: "#000000") // Чистый черный, прозрачность задается в градиенте
    private static let darkDiscoverCardScrim = Color(hex: "#000000")

    private static let lightTabBarInactiveIcon = Color(hex: "#9E8CD9")
    private static let darkTabBarInactiveIcon = Color(hex: "#7E6EBA")

    private static let lightTabBarInactiveTitle = Color(hex: "#A390A8")
    private static let darkTabBarInactiveTitle = Color(hex: "#817285")

    private static let lightGlassBorderHighlight = Color(hex: "#FFFFFF").opacity(0.6)
    private static let darkGlassBorderHighlight = Color(hex: "#FFFFFF").opacity(0.15) // Тонкий светящийся стык для темной темы

    // MARK: Additional Semantic Colors

    private static let lightCardSurface = Color(hex: "#FFFFFF")
    private static let darkCardSurface = Color(hex: "#14101F") // Эффект многослойности: карточка чуть светлее подложки

    private static let lightElevatedSurface = Color(hex: "#FFF8F6")
    private static let darkElevatedSurface = Color(hex: "#1C162A")

    private static let lightFieldBackground = Color(hex: "#F5EFF2") // Инпуты слегка утоплены относительно фона
    private static let darkFieldBackground = Color(hex: "#171224")

    private static let lightHairline = Color(hex: "#EFE5EA")
    private static let darkHairline = Color(hex: "#2C2036")

    private static let lightDisabled = Color(hex: "#C9B8C0")
    private static let darkDisabled = Color(hex: "#6F6073")

    private static let lightSuccess = Color(hex: "#10D37F")
    private static let darkSuccess = Color(hex: "#2CE491")

    private static let lightWarning = Color(hex: "#C67A22")
    private static let darkWarning = Color(hex: "#E0A64A")

    private static let lightError = Color(hex: "#C9364F")
    private static let darkError = Color(hex: "#FF6B7E")

    private static let lightChatBubbleMine = Color(hex: "#E8DEFF")
    private static let darkChatBubbleMine = Color(hex: "#2F2447")

    // Warm far stop of the outgoing bubble gradient: lavender melts into a rose blush,
    // so my messages feel affectionate instead of office-lilac. Dark theme gets a wine tint.
    private static let lightChatBubbleMineBlush = Color(hex: "#FBD5E4")
    private static let darkChatBubbleMineBlush = Color(hex: "#46283F")

    // Incoming bubbles: a whisper of warmth (ivory -> soft peach) instead of flat card white.
    private static let lightChatBubbleOtherTop = Color(hex: "#FFFFFF")
    private static let darkChatBubbleOtherTop = Color(hex: "#171123")

    private static let lightChatBubbleOtherWarm = Color(hex: "#FFF2EA")
    private static let darkChatBubbleOtherWarm = Color(hex: "#221527")

    // Bubble shadows carry a violet-pink tint instead of neutral gray to keep the chat warm.
    private static let lightChatBubbleShadow = Color(hex: "#B04A80")
    private static let darkChatBubbleShadow = Color(hex: "#000000")

    // Избавились от синего из «Госуслуг», теперь здесь фирменный фиолетовый акцент JustTwo
    private static let lightChatReactionSelected = Color(hex: "#6344E3")
    private static let darkChatReactionSelected = Color(hex: "#7956FA")

    // MARK: Semantic — Core UI

    static var surface: Color {
        dynamic(light: lightSurface, dark: darkSurface)
    }

    static var onAccentText: Color {
        dynamic(light: lightOnAccentText, dark: darkOnAccentText)
    }

    static var brandPrimary: Color {
        dynamic(light: lightBrandPrimary, dark: darkBrandPrimary)
    }

    static var brandPrimaryGlow: Color {
        dynamic(light: lightBrandPrimaryGlow, dark: darkBrandPrimaryGlow)
    }

    static var indigo: Color {
        dynamic(light: lightIndigo, dark: darkIndigo)
    }

    static var glassBorderHighlight: Color {
        dynamic(light: lightGlassBorderHighlight, dark: darkGlassBorderHighlight)
    }

    static var cardSurface: Color {
        dynamic(light: lightCardSurface, dark: darkCardSurface)
    }

    static var elevatedSurface: Color {
        dynamic(light: lightElevatedSurface, dark: darkElevatedSurface)
    }

    static var fieldBackground: Color {
        dynamic(light: lightFieldBackground, dark: darkFieldBackground)
    }

    static var hairline: Color {
        dynamic(light: lightHairline, dark: darkHairline)
    }

    static var primaryText: Color {
        discoverPrimaryText
    }

    static var secondaryText: Color {
        discoverSecondaryText
    }

    static var success: Color {
        dynamic(light: lightSuccess, dark: darkSuccess)
    }

    static var error: Color {
        dynamic(light: lightError, dark: darkError)
    }

    static var chatBubbleMine: Color {
        dynamic(light: lightChatBubbleMine, dark: darkChatBubbleMine)
    }

    static var chatBubbleOther: Color {
        cardSurface
    }

    static var chatBubbleMineGradient: LinearGradient {
        LinearGradient(
            colors: [
                chatBubbleMine,
                dynamic(light: lightChatBubbleMineBlush, dark: darkChatBubbleMineBlush)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var chatBubbleOtherGradient: LinearGradient {
        LinearGradient(
            colors: [
                dynamic(light: lightChatBubbleOtherTop, dark: darkChatBubbleOtherTop),
                dynamic(light: lightChatBubbleOtherWarm, dark: darkChatBubbleOtherWarm)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var chatBubbleShadow: Color {
        dynamic(light: lightChatBubbleShadow, dark: darkChatBubbleShadow)
    }

    static var chatSenderNameGradient: LinearGradient {
        LinearGradient(
            colors: [.discoverViolet, .discoverPinkLight],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var chatReactionSelected: Color {
        dynamic(light: lightChatReactionSelected, dark: darkChatReactionSelected)
    }

    // MARK: Semantic — Discover

    static var discoverPrimaryText: Color {
        dynamic(light: lightDiscoverPrimaryText, dark: darkDiscoverPrimaryText)
    }

    static var discoverSecondaryText: Color {
        dynamic(light: lightDiscoverSecondaryText, dark: darkDiscoverSecondaryText)
    }

    static var discoverViolet: Color {
        dynamic(light: lightDiscoverViolet, dark: darkDiscoverViolet)
    }

    static var discoverVioletLight: Color {
        dynamic(light: lightDiscoverVioletLight, dark: darkDiscoverVioletLight)
    }

    static var tabBarInactiveIcon: Color {
        dynamic(light: lightTabBarInactiveIcon, dark: darkTabBarInactiveIcon)
    }

    static var tabBarInactiveTitle: Color {
        dynamic(light: lightTabBarInactiveTitle, dark: darkTabBarInactiveTitle)
    }

    static var discoverPink: Color {
        dynamic(light: lightDiscoverPink, dark: darkDiscoverPink)
    }

    static var discoverCardShadow: Color {
        dynamic(light: lightDiscoverCardShadow, dark: darkDiscoverCardShadow)
    }

    static var discoverOnline: Color {
        dynamic(light: lightDiscoverOnline, dark: darkDiscoverOnline)
    }

    static var discoverCardScrim: Color {
        dynamic(light: lightDiscoverCardScrim, dark: darkDiscoverCardScrim)
    }

    static var discoverOnPhotoText: Color {
        onAccentText
    }

    // MARK: Semantic — Supporting Tokens

    static var brandPrimaryPressed: Color {
        dynamic(light: lightBrandPrimaryPressed, dark: darkBrandPrimaryPressed)
    }

    static var brandGradientEnd: Color {
        dynamic(light: lightBrandGradientEnd, dark: darkBrandGradientEnd)
    }

    static var disabled: Color {
        dynamic(light: lightDisabled, dark: darkDisabled)
    }

    static var warning: Color {
        dynamic(light: lightWarning, dark: darkWarning)
    }

    static var discoverPinkLight: Color {
        dynamic(light: lightDiscoverPinkLight, dark: darkDiscoverPinkLight)
    }

    static var discoverMockLavender: Color {
        dynamic(light: lightDiscoverMockLavender, dark: darkDiscoverMockLavender)
    }

    static var discoverMockPeach: Color {
        dynamic(light: lightDiscoverMockPeach, dark: darkDiscoverMockPeach)
    }

    // MARK: Gradients

    static var discoverBackgroundGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: dynamic(light: lightDiscoverBackgroundTop, dark: darkDiscoverBackgroundTop), location: 0),
                .init(color: dynamic(light: lightDiscoverBackgroundMiddle, dark: darkDiscoverBackgroundMiddle), location: 0.55),
                .init(color: dynamic(light: lightDiscoverBackgroundBottom, dark: darkDiscoverBackgroundBottom), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var authBackgroundGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: dynamic(light: lightDiscoverBackgroundTop, dark: darkDiscoverBackgroundTop), location: 0),
                .init(color: dynamic(light: lightDiscoverBackgroundBottom, dark: darkDiscoverBackgroundMiddle), location: 0.46),
                .init(color: dynamic(light: lightDiscoverBackgroundMiddle, dark: darkDiscoverBackgroundBottom), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var discoverSelectedGradient: LinearGradient {
        LinearGradient(
            colors: [.discoverViolet, .discoverVioletLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var discoverMoodGradient: LinearGradient {
        LinearGradient(
            colors: [.discoverPink, .discoverPinkLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var chatSendButtonGradient: LinearGradient {
        LinearGradient(
            colors: [.brandPrimary, .indigo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var discoverMockProfileGradient: LinearGradient {
        LinearGradient(
            colors: [.discoverMockLavender, .discoverMockPeach],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var discoverCardOverlayGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.35),
                .init(color: discoverCardScrim.opacity(0.55), location: 0.65),
                .init(color: discoverCardScrim.opacity(0.90), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var discoverCardTopVignette: LinearGradient {
        LinearGradient(
            colors: [discoverCardScrim.opacity(0.22), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var brandPrimaryGradient: LinearGradient {
        LinearGradient(
            colors: [.brandPrimary, .brandGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var brandPrimaryPressedGradient: LinearGradient {
        LinearGradient(
            colors: [.brandPrimaryPressed, .brandPrimary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Helpers

    private static func dynamic(light: Color, dark: Color) -> Color {
#if canImport(UIKit)
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
#elseif os(macOS)
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        }))
#else
        light
#endif
    }
}

// MARK: - Typography

extension Font {
    enum App {
        private static let fontNamePrefix = "Manrope"

        private static func manropeName(for weight: Weight) -> String {
            switch weight {
            case .bold:
                return "\(fontNamePrefix)-Bold"
            case .heavy, .black:
                return "\(fontNamePrefix)-ExtraBold"
            case .semibold:
                return "\(fontNamePrefix)-SemiBold"
            case .medium:
                return "\(fontNamePrefix)-Medium"
            default:
                return "\(fontNamePrefix)-Regular"
            }
        }

        static func manrope(
            size: CGFloat,
            weight: Weight = .regular,
            relativeTo textStyle: TextStyle = .body
        ) -> Font {
            .custom(manropeName(for: weight), size: size, relativeTo: textStyle)
        }

        static func title(size: CGFloat, weight: Weight = .bold) -> Font {
            manrope(size: size, weight: weight, relativeTo: .title)
        }

        static func headline(size: CGFloat, weight: Weight = .semibold) -> Font {
            manrope(size: size, weight: weight, relativeTo: .headline)
        }

        static func body(size: CGFloat = 16, weight: Weight = .regular) -> Font {
            manrope(size: size, weight: weight, relativeTo: .body)
        }

        static func subheadline(size: CGFloat = 15, weight: Weight = .regular) -> Font {
            manrope(size: size, weight: weight, relativeTo: .subheadline)
        }

        static func caption(size: CGFloat = 12, weight: Weight = .regular) -> Font {
            manrope(size: size, weight: weight, relativeTo: .caption)
        }

        static func footnote(weight: Weight = .regular) -> Font {
            manrope(size: 13, weight: weight, relativeTo: .footnote)
        }

        static var button: Font {
            headline(size: 16, weight: .bold)
        }

        static var screenTitle: Font {
            title(size: 30, weight: .heavy)
        }

        static var subtitle: Font {
            subheadline(size: 15, weight: .medium)
        }
    }
}

// MARK: - Layout

enum AppSpacing {
    static let sm: CGFloat = 12
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum AppCornerRadius {
    static let field: CGFloat = 18
    static let photoCell: CGFloat = 20
    static let button: CGFloat = 26
    static let card: CGFloat = 24
    static let profileCard: CGFloat = 32
    static let sheet: CGFloat = 28
}

// MARK: - Hex Support

extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let a, r, g, b: UInt64
        switch sanitized.count {
        case 3:
            (a, r, g, b) = (255, (value >> 8) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, value >> 16, value >> 8 & 0xFF, value & 0xFF)
        case 8:
            (a, r, g, b) = (value >> 24, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
