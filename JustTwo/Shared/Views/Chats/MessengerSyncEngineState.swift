import Foundation

enum MessengerSyncEngineState: String, Sendable, Equatable {
    case idle
    case bootstrapping
    case syncing
    case failed
    case backoff
    case needsFullRefresh
}

enum MessengerSyncEngineError: Error, Equatable {
    case revisionGapDetected
    case outOfOrderRevision
    case cursorAheadOfServer
    case unauthorized
    case notAuthenticated
}

enum MessengerSyncEngineLimits {
    nonisolated static let maxPagesPerRun = 20

    static func backoffDelay(forFailureCount count: Int) -> TimeInterval {
        switch count {
        case 0, 1:
            return 5
        case 2:
            return 15
        default:
            return 60
        }
    }
}
