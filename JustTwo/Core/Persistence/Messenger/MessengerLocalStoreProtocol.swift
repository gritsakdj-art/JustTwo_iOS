import Foundation

@MainActor
protocol MessengerLocalStoreProtocol: AnyObject {
    func resetAllMessengerData() async throws

    func upsertConversations(_ conversations: [ConversationDTO]) async throws
    func fetchLocalConversations() async throws -> [LocalConversationSnapshot]
    func patchConversationFromMessage(_ message: MessageDTO, unreadCount: Int?) async throws
    func patchConversationActivity(
        conversationID: UUID,
        lastMessageAt: Date?,
        unreadCount: Int?
    ) async throws
    func upsertLastMessageSnapshot(_ message: MessageDTO) async throws

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

    func updateAttachmentMediaCacheMetadata(
        attachmentID: String,
        variant: MessengerMediaVariant,
        byteSize: Int,
        cachedAt: Date
    ) async throws
    func recordAttachmentMediaAccess(
        attachmentID: String,
        variant: MessengerMediaVariant,
        accessedAt: Date
    ) async throws
    func clearAttachmentMediaCacheMetadata(attachmentID: String) async throws
    func fetchAttachmentLocalCacheKeys() async throws -> Set<String>
}
