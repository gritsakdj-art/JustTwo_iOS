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

    func createTextOutboxItem(
        conversationID: UUID,
        clientMessageID: String,
        body: String,
        replyToMessageID: UUID?
    ) async throws -> MessengerOutboxItemSnapshot

    func fetchPendingOutboxItems() async throws -> [MessengerOutboxItemSnapshot]

    func fetchOutboxItems(conversationID: UUID) async throws -> [MessengerOutboxItemSnapshot]

    func fetchOutboxItem(clientMessageID: String) async throws -> MessengerOutboxItemSnapshot?

    func markOutboxSending(clientMessageID: String) async throws

    func markOutboxFailed(
        clientMessageID: String,
        errorCode: String?,
        nextRetryAt: Date?
    ) async throws

    func markOutboxPending(clientMessageID: String) async throws

    func markOutboxSent(clientMessageID: String, serverMessageID: UUID) async throws

    func deleteOutboxItem(clientMessageID: String) async throws

    func deleteOutboxItems(conversationID: UUID) async throws

    func resetStaleOutboxSendingItems() async throws -> Int

    func clearOutbox() async throws

    func createImageOutboxItem(
        conversationID: UUID,
        clientMessageID: String,
        caption: String?,
        replyToMessageID: UUID?,
        pendingMediaID: String,
        localRelativePath: String,
        contentType: String,
        byteSize: Int,
        width: Int,
        height: Int
    ) async throws -> MessengerOutboxItemSnapshot

    func fetchPendingMedia(clientMessageID: String) async throws -> MessengerPendingMediaSnapshot?

    func fetchPendingMedia(pendingMediaID: String) async throws -> MessengerPendingMediaSnapshot?

    func deletePendingMedia(clientMessageID: String) async throws

    func clearPendingMedia() async throws

    func fetchPendingMediaRelativePaths() async throws -> Set<String>
}
