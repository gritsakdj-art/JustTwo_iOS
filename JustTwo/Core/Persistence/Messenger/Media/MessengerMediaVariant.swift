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

    var softLimitBytes: Int64 { targetBytesAfterCleanup }
    var hardLimitBytes: Int64 { maxBytes }

    static let `default` = MessengerMediaCacheCleanupPolicy(
        maxBytes: 300 * 1_024 * 1_024,
        targetBytesAfterCleanup: 200 * 1_024 * 1_024,
        maxAgeDays: 90
    )
}
