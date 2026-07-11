import Foundation
import SwiftData

/// Durable, account-scoped record of the highest authoritative proven-safe
/// delivery boundary for which a backend delivered-ACK may still be required.
///
/// The boundary `(createdAt, messageID)` is the canonical PR20D1 receipt
/// boundary: acknowledging `messageID` tells the backend the client has
/// applied the whole inbound prefix `<=` this boundary. Persisting it means a
/// pending ACK survives process termination and can be replayed on cold start.
@Model
final class LocalMessengerPendingDeliveryReceipt {
    /// Stable composite key `ownerProfileID|conversationID`. Never logged in full.
    @Attribute(.unique) var key: String

    var ownerProfileID: UUID
    var conversationID: UUID
    var createdAt: Date
    var messageID: UUID
    var updatedAt: Date

    init(
        key: String,
        ownerProfileID: UUID,
        conversationID: UUID,
        createdAt: Date,
        messageID: UUID,
        updatedAt: Date
    ) {
        self.key = key
        self.ownerProfileID = ownerProfileID
        self.conversationID = conversationID
        self.createdAt = createdAt
        self.messageID = messageID
        self.updatedAt = updatedAt
    }

    static func makeKey(ownerProfileID: UUID, conversationID: UUID) -> String {
        "\(ownerProfileID.uuidString)|\(conversationID.uuidString)"
    }
}
