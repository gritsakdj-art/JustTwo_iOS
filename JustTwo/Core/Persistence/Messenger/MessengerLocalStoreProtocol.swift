import Foundation

@MainActor
protocol MessengerLocalStoreProtocol: AnyObject {
    func resetAllMessengerData() async throws

    func upsertConversations(_ conversations: [ConversationDTO]) async throws
    func fetchLocalConversations() async throws -> [LocalConversationSnapshot]

    func upsertMessages(
        _ messages: [MessageDTO],
        conversationID: UUID
    ) async throws
    func fetchLocalMessages(
        conversationID: UUID,
        limit: Int,
        before: Date?
    ) async throws -> [LocalMessageSnapshot]

    func markMessageDeleted(messageID: UUID, deletedAt: Date?) async throws
    func upsertReactions(from message: MessageDTO) async throws
    func applyReceipt(_ receipt: MessengerReceiptDTO) async throws

    func upsertSyncMetadata(_ metadata: LocalMessengerSyncMetadataSnapshot) async throws
    func fetchSyncMetadata() async throws -> LocalMessengerSyncMetadataSnapshot?
}
