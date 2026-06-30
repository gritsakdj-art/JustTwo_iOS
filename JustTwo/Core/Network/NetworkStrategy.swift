import Foundation

enum NetworkStrategy: Sendable {

    case primary
    case ephemeral
    case forcedFresh
    case lastResort
    case splashPrimary
    case splashEphemeral

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
        case .splashPrimary:
            return "splashPrimary"
        case .splashEphemeral:
            return "splashEphemeral"
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
        case .splashPrimary:
            return URLSessionProvider.splashSession
        case .splashEphemeral:
            return URLSessionProvider.splashEphemeralSession
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

    /// Short timeouts for splash auth probes (~10s per attempt).
    nonisolated static let splashFlow: [NetworkStrategy] = [
        .splashPrimary,
        .splashEphemeral
    ]
}
