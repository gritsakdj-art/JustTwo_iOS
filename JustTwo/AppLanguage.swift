import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case italian = "it"
    case arabic = "ar"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        default:
            return Locale(identifier: rawValue)
        }
    }

    var title: Text {
        switch self {
        case .system:
            return Text("settings.language.system")
        case .english:
            return Text("English")
        case .russian:
            return Text("Русский")
        case .german:
            return Text("Deutsch")
        case .spanish:
            return Text("Español")
        case .french:
            return Text("Français")
        case .italian:
            return Text("Italiano")
        case .arabic:
            return Text("العربية")
        }
    }

    var subtitle: String? {
        switch self {
        case .system:
            return nil
        default:
            return rawValue.uppercased()
        }
    }

    var iconName: String {
        switch self {
        case .system:
            return "globe"
        default:
            return "textformat"
        }
    }

    func layoutDirection(system: LayoutDirection) -> LayoutDirection {
        switch self {
        case .system:
            return system
        case .arabic:
            return .rightToLeft
        default:
            return .leftToRight
        }
    }
}
