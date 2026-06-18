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

    private static let lightSurface = Color(hex: "#FFFFFF")
    private static let darkSurface = Color(hex: "#171421")

    private static let lightOnAccentText = Color(hex: "#FFFFFF")
    private static let darkOnAccentText = Color(hex: "#FFFFFF")

    private static let lightBrandPrimary = Color(hex: "#7C4DDB")
    private static let darkBrandPrimary = Color(hex: "#A47CFF")

    private static let lightBrandPrimaryPressed = Color(hex: "#6738C8")
    private static let darkBrandPrimaryPressed = Color(hex: "#8F63F2")

    // MARK: Discover

    private static let lightDiscoverBackgroundTop = Color(hex: "#F0EBFF")
    private static let darkDiscoverBackgroundTop = Color(hex: "#161221")

    private static let lightDiscoverBackgroundMiddle = Color(hex: "#FCE8F3")
    private static let darkDiscoverBackgroundMiddle = Color(hex: "#231524")

    private static let lightDiscoverBackgroundBottom = Color(hex: "#E8F0FF")
    private static let darkDiscoverBackgroundBottom = Color(hex: "#101A2A")

    private static let lightDiscoverPrimaryText = Color(hex: "#12103A")
    private static let darkDiscoverPrimaryText = Color(hex: "#F8F4FF")

    private static let lightDiscoverSecondaryText = Color(hex: "#7A7499")
    private static let darkDiscoverSecondaryText = Color(hex: "#BDB4D6")

    private static let lightDiscoverViolet = Color(hex: "#7C4DDB")
    private static let darkDiscoverViolet = Color(hex: "#A47CFF")

    private static let lightDiscoverVioletLight = Color(hex: "#B06DE8")
    private static let darkDiscoverVioletLight = Color(hex: "#C39BFF")

    private static let lightDiscoverPink = Color(hex: "#E55A7A")
    private static let darkDiscoverPink = Color(hex: "#FF7EA3")

    private static let lightDiscoverPinkLight = Color(hex: "#F59AC9")
    private static let darkDiscoverPinkLight = Color(hex: "#FFB0D3")

    private static let lightDiscoverCardShadow = Color(hex: "#501EA0")
    private static let darkDiscoverCardShadow = Color(hex: "#A47CFF")

    private static let lightDiscoverMockLavender = Color(hex: "#C9BEED")
    private static let darkDiscoverMockLavender = Color(hex: "#4B3F6D")

    private static let lightDiscoverMockPeach = Color(hex: "#FFE0C4")
    private static let darkDiscoverMockPeach = Color(hex: "#5A3B3B")

    private static let lightDiscoverOnline = Color(hex: "#5DFFA0")
    private static let darkDiscoverOnline = Color(hex: "#6DFFB0")

    // MARK: Semantic

    static var surface: Color {
        dynamic(light: lightSurface, dark: darkSurface)
    }

    static var onAccentText: Color {
        dynamic(light: lightOnAccentText, dark: darkOnAccentText)
    }

    static var brandPrimary: Color {
        dynamic(light: lightBrandPrimary, dark: darkBrandPrimary)
    }

    static var brandPrimaryPressed: Color {
        dynamic(light: lightBrandPrimaryPressed, dark: darkBrandPrimaryPressed)
    }

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

    static var discoverPink: Color {
        dynamic(light: lightDiscoverPink, dark: darkDiscoverPink)
    }

    static var discoverPinkLight: Color {
        dynamic(light: lightDiscoverPinkLight, dark: darkDiscoverPinkLight)
    }

    static var discoverCardShadow: Color {
        dynamic(light: lightDiscoverCardShadow, dark: darkDiscoverCardShadow)
    }

    static var discoverMockLavender: Color {
        dynamic(light: lightDiscoverMockLavender, dark: darkDiscoverMockLavender)
    }

    static var discoverMockPeach: Color {
        dynamic(light: lightDiscoverMockPeach, dark: darkDiscoverMockPeach)
    }

    static var discoverOnline: Color {
        dynamic(light: lightDiscoverOnline, dark: darkDiscoverOnline)
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

    static var discoverMockProfileGradient: LinearGradient {
        LinearGradient(
            colors: [.discoverMockLavender, .discoverPinkLight, .discoverMockPeach],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var discoverCardOverlayGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.35),
                .init(color: discoverPrimaryText.opacity(0.55), location: 0.65),
                .init(color: discoverPrimaryText.opacity(0.88), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var discoverCardTopVignette: LinearGradient {
        LinearGradient(
            colors: [discoverPrimaryText.opacity(0.18), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var brandPrimaryGradient: LinearGradient {
        LinearGradient(
            colors: [.brandPrimary, .discoverVioletLight],
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
        static var screenTitle: Font {
            .system(.title, design: .rounded, weight: .bold)
        }

        static var subtitle: Font {
            .system(.subheadline, design: .rounded, weight: .regular)
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
