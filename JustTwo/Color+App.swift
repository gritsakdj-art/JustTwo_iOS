import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - JustTwo Design System

extension Color {
    // MARK: Base

    private static let lightSurface = Color(hex: "#FFFBF7")
    private static let darkSurface = Color(hex: "#100D18")

    private static let lightOnAccentText = Color(hex: "#FFFFFF")
    private static let darkOnAccentText = Color(hex: "#FFFFFF")

    private static let lightBrandPrimary = Color(hex: "#B8325E")
    private static let darkBrandPrimary = Color(hex: "#C94268")

    private static let lightBrandPrimaryPressed = Color(hex: "#8F2347")
    private static let darkBrandPrimaryPressed = Color(hex: "#A83356")

    private static let lightBrandGradientEnd = Color(hex: "#6E56CF")
    private static let darkBrandGradientEnd = Color(hex: "#7E5FD4")

    private static let lightIndigo = Color(hex: "#4F46E5")
    private static let darkIndigo = Color(hex: "#818CF8")

    private static let lightBrandPrimaryGlow = Color(hex: "#FF6B8A")
    private static let darkBrandPrimaryGlow = Color(hex: "#FF5F87")

    // MARK: Discover

    private static let lightDiscoverBackgroundTop = Color(hex: "#FFFBF7")
    private static let darkDiscoverBackgroundTop = Color(hex: "#0F0B16")

    private static let lightDiscoverBackgroundMiddle = Color(hex: "#FFE6EA")
    private static let darkDiscoverBackgroundMiddle = Color(hex: "#211224")

    private static let lightDiscoverBackgroundBottom = Color(hex: "#F3ECFF")
    private static let darkDiscoverBackgroundBottom = Color(hex: "#0E1826")

    private static let lightDiscoverPrimaryText = Color(hex: "#24151F")
    private static let darkDiscoverPrimaryText = Color(hex: "#FFF7FB")

    private static let lightDiscoverSecondaryText = Color(hex: "#75616B")
    private static let darkDiscoverSecondaryText = Color(hex: "#CDBDC8")

    private static let lightDiscoverViolet = Color(hex: "#6E56CF")
    private static let darkDiscoverViolet = Color(hex: "#7E5FD4")

    private static let lightDiscoverVioletLight = Color(hex: "#7758D5")
    private static let darkDiscoverVioletLight = Color(hex: "#9A82F0")

    private static let lightDiscoverPink = Color(hex: "#B8325E")
    private static let darkDiscoverPink = Color(hex: "#C94268")

    private static let lightDiscoverPinkLight = Color(hex: "#C3476B")
    private static let darkDiscoverPinkLight = Color(hex: "#C44B59")

    private static let lightDiscoverCardShadow = Color(hex: "#5A3142")
    private static let darkDiscoverCardShadow = Color(hex: "#05030A")

    private static let lightDiscoverMockLavender = Color(hex: "#F1E7FF")
    private static let darkDiscoverMockLavender = Color(hex: "#2E2642")

    private static let lightDiscoverMockPeach = Color(hex: "#FFE1D8")
    private static let darkDiscoverMockPeach = Color(hex: "#3A2028")

    private static let lightDiscoverOnline = Color(hex: "#18C97A")
    private static let darkDiscoverOnline = Color(hex: "#35D989")

    private static let lightDiscoverCardScrim = Color(hex: "#110812")
    private static let darkDiscoverCardScrim = Color(hex: "#04020A")

    private static let lightTabBarInactiveIcon = Color(hex: "#8A76C9")
    private static let darkTabBarInactiveIcon = Color(hex: "#A696DE")

    private static let lightTabBarInactiveTitle = Color(hex: "#8E7A93")
    private static let darkTabBarInactiveTitle = Color(hex: "#B8A9C1")

    private static let lightGlassBorderHighlight = Color(hex: "#FFFFFF")
    private static let darkGlassBorderHighlight = Color(hex: "#F1EAFB")

    // MARK: Additional Semantic Colors

    private static let lightCardSurface = Color(hex: "#FFFFFF")
    private static let darkCardSurface = Color(hex: "#191522")

    private static let lightElevatedSurface = Color(hex: "#FFF5F2")
    private static let darkElevatedSurface = Color(hex: "#241A2D")

    private static let lightFieldBackground = Color(hex: "#FFFFFF")
    private static let darkFieldBackground = Color(hex: "#1D1727")

    private static let lightHairline = Color(hex: "#E8D9E1")
    private static let darkHairline = Color(hex: "#36283F")

    private static let lightDisabled = Color(hex: "#C9B8C0")
    private static let darkDisabled = Color(hex: "#6F6073")

    private static let lightSuccess = Color(hex: "#18C97A")
    private static let darkSuccess = Color(hex: "#35D989")

    private static let lightWarning = Color(hex: "#C67A22")
    private static let darkWarning = Color(hex: "#E0A64A")

    private static let lightError = Color(hex: "#C9364F")
    private static let darkError = Color(hex: "#FF6B7E")

    private static let lightChatBubbleMine = Color(hex: "#E8DEFF")
    private static let darkChatBubbleMine = Color(hex: "#3A2F56")

    private static let lightChatReactionSelected = Color(hex: "#005493")
    private static let darkChatReactionSelected = Color(hex: "#005493")

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

    /// Darkening layer for profile photos — always a deep tone, independent of screen text color.
    static var discoverCardScrim: Color {
        dynamic(light: lightDiscoverCardScrim, dark: darkDiscoverCardScrim)
    }

    /// Text placed on top of profile photos over `discoverCardScrim`.
    static var discoverOnPhotoText: Color {
        onAccentText
    }

    // MARK: Semantic — Supporting Tokens
    //
    // Used by gradients, state styles, placeholders, disabled controls,
    // warnings, and future UI components.

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
                .init(
                    color: dynamic(light: lightDiscoverBackgroundTop, dark: darkDiscoverBackgroundTop),
                    location: 0
                ),
                .init(
                    color: dynamic(light: lightDiscoverBackgroundMiddle, dark: darkDiscoverBackgroundMiddle),
                    location: 0.55
                ),
                .init(
                    color: dynamic(light: lightDiscoverBackgroundBottom, dark: darkDiscoverBackgroundBottom),
                    location: 1
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var authBackgroundGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(
                    color: dynamic(light: lightDiscoverBackgroundTop, dark: darkDiscoverBackgroundTop),
                    location: 0
                ),
                .init(
                    color: dynamic(light: lightDiscoverBackgroundBottom, dark: darkDiscoverBackgroundMiddle),
                    location: 0.46
                ),
                .init(
                    color: dynamic(light: lightDiscoverBackgroundMiddle, dark: darkDiscoverBackgroundBottom),
                    location: 1
                )
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
        private static func manropeName(for weight: Weight) -> String {
            switch weight {
            case .bold:
                return "Manrope-Bold"
            case .heavy, .black:
                return "Manrope-ExtraBold"
            case .semibold:
                return "Manrope-SemiBold"
            case .medium:
                return "Manrope-Medium"
            default:
                return "Manrope-Regular"
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
