import Foundation

struct MessageReceiptBoundary: Sendable, Equatable, Comparable {
    let createdAt: Date
    let messageID: UUID

    init?(message: MessageDTO) {
        guard let createdAt = message.createdAt else { return nil }
        self.createdAt = createdAt
        self.messageID = message.id
    }

    init(createdAt: Date, messageID: UUID) {
        self.createdAt = createdAt
        self.messageID = messageID
    }

    static func < (lhs: MessageReceiptBoundary, rhs: MessageReceiptBoundary) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.messageID.postgresOrderedBytes.lexicographicallyPrecedes(rhs.messageID.postgresOrderedBytes)
    }
}

enum DeliveryCoverageEvidence: Sendable, Equatable {
    case previewOnly
    case partialRESTPage
    case paginationPage
    case realtimeUnverified(connectionEpoch: Int)
    case authoritativeSync(fromRevision: Int64, throughRevision: Int64)
    case persistedSafeBoundary

    var diagnosticName: String {
        switch self {
        case .previewOnly:
            return "previewOnly"
        case .partialRESTPage:
            return "partialRESTPage"
        case .paginationPage:
            return "paginationPage"
        case .realtimeUnverified:
            return "realtimeUnverified"
        case .authoritativeSync:
            return "authoritativeSync"
        case .persistedSafeBoundary:
            return "persistedSafeBoundary"
        }
    }

    var permitsAck: Bool {
        switch self {
        case .authoritativeSync, .persistedSafeBoundary:
            return true
        case .previewOnly, .partialRESTPage, .paginationPage, .realtimeUnverified:
            return false
        }
    }
}

private extension UUID {
    var postgresOrderedBytes: [UInt8] {
        withUnsafeBytes(of: uuid) { Array($0) }
    }
}
