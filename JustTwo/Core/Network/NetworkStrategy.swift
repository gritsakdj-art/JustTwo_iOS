import Foundation

enum NetworkStrategy: Sendable {

    case primary
    case ephemeral
    case forcedFresh
    case lastResort

    nonisolated var name: String {
        switch self {
        case .primary:
            return "primary"
        case .ephemeral:
            return "ephemeral"
        case .forcedFresh:
            return "forcedFresh"
        case .lastResort:
            return "lastResort"
        }
    }

    nonisolated var session: URLSession {
        switch self {
        case .primary:
            return URLSessionProvider.session
        case .ephemeral:
            return URLSessionProvider.fallbackSession
        case .forcedFresh:
            return URLSessionProvider.forcedFreshSession
        case .lastResort:
            return URLSessionProvider.lastResortSession
        }
    }

    nonisolated static let defaultFlow: [NetworkStrategy] = [
        .primary,
        .ephemeral,
        .forcedFresh,
        .lastResort
    ]

    nonisolated static let lightFlow: [NetworkStrategy] = [
        .primary,
        .ephemeral
    ]
}
