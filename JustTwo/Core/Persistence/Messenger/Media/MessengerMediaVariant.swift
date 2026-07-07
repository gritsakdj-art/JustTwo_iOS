import Foundation

enum MessengerMediaVariant: String, Codable, Sendable, CaseIterable {
    case thumbnail
    case full

    nonisolated var fileName: String {
        switch self {
        case .thumbnail:
            return "thumb.jpg"
        case .full:
            return "full.jpg"
        }
    }
}

struct MessengerMediaCacheCleanupPolicy: Sendable, Equatable {
    let maxBytes: Int64
    let targetBytesAfterCleanup: Int64
    let maxAgeDays: Int

    static let `default` = MessengerMediaCacheCleanupPolicy(
        maxBytes: 300 * 1_024 * 1_024,
        targetBytesAfterCleanup: 240 * 1_024 * 1_024,
        maxAgeDays: 90
    )
}
