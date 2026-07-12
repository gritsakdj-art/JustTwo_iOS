import Foundation

enum MessengerReceiptKind: String, Sendable, Equatable {
    case delivered
    case read
}

struct MessengerReceiptApplyResult: Sendable, Equatable {
    let didAdvanceParticipantBoundary: Bool
    let updatedMessageCount: Int
    let updatedConversationPreview: Bool
    let targetMessageFound: Bool
    let requiresSyncRepair: Bool
    let previewDeliveryStatus: MessageDeliveryStatus?

    static let noop = MessengerReceiptApplyResult(
        didAdvanceParticipantBoundary: false,
        updatedMessageCount: 0,
        updatedConversationPreview: false,
        targetMessageFound: false,
        requiresSyncRepair: false,
        previewDeliveryStatus: nil
    )

    static func targetMissing(requiresRepair: Bool = true) -> MessengerReceiptApplyResult {
        MessengerReceiptApplyResult(
            didAdvanceParticipantBoundary: false,
            updatedMessageCount: 0,
            updatedConversationPreview: false,
            targetMessageFound: false,
            requiresSyncRepair: requiresRepair,
            previewDeliveryStatus: nil
        )
    }
}

enum MessengerReceiptBoundaryMath {
    static func boundary(
        from receipt: LocalMessengerReceipt,
        kind: MessengerReceiptKind
    ) -> MessageReceiptBoundary? {
        switch kind {
        case .delivered:
            guard let messageIDString = receipt.lastDeliveredMessageID,
                  let messageID = UUID(uuidString: messageIDString),
                  let createdAt = receipt.lastDeliveredAt else {
                return nil
            }
            return MessageReceiptBoundary(createdAt: createdAt, messageID: messageID)
        case .read:
            guard let messageIDString = receipt.lastReadMessageID,
                  let messageID = UUID(uuidString: messageIDString),
                  let createdAt = receipt.lastReadAt else {
                return nil
            }
            return MessageReceiptBoundary(createdAt: createdAt, messageID: messageID)
        }
    }

    static func shouldAdvance(
        incoming: MessageReceiptBoundary,
        over existing: MessageReceiptBoundary?
    ) -> Bool {
        guard let existing else { return true }
        return incoming > existing
    }

    static func upgradedStatus(
        current: MessageDeliveryStatus?,
        applying kind: MessengerReceiptKind
    ) -> MessageDeliveryStatus? {
        let currentRank = current?.rank ?? MessageDeliveryStatus.sent.rank
        let target: MessageDeliveryStatus = kind == .read ? .read : .delivered
        guard target.rank > currentRank else { return nil }
        return target
    }

    static func messageQualifiesForReceipt(
        senderProfileID: String,
        ownerProfileID: UUID,
        deletedAt: Date?,
        localState: String,
        messageCreatedAt: Date,
        boundary: MessageReceiptBoundary
    ) -> Bool {
        guard senderProfileID == ownerProfileID.uuidString else { return false }
        guard deletedAt == nil else { return false }
        guard localState == LocalMessengerMessageState.serverConfirmed.rawValue else { return false }
        return messageCreatedAt <= boundary.createdAt
    }
}
