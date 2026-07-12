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

    func patchConversationOutgoingDeliveryStatus(
        conversationID: UUID,
        deliveryStatus: MessageDeliveryStatus
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

    /// Applies a realtime `conversation.delivered` / `conversation.read` boundary
    /// monotonically against local participant receipt state and outgoing message
    /// delivery statuses. One atomic `ModelContext.save()` per successful apply.
    func applyRealtimeReceipt(
        ownerProfileID: UUID,
        conversationID: UUID,
        participantProfileID: UUID,
        kind: MessengerReceiptKind,
        boundaryMessageID: UUID
    ) async throws -> MessengerReceiptApplyResult

    func upsertSyncMetadata(_ metadata: LocalMessengerSyncMetadataSnapshot) async throws
    func fetchSyncMetadata() async throws -> LocalMessengerSyncMetadataSnapshot?

    /// Atomically advances the global sync cursor (when `advancedRevision != nil`)
    /// and monotonically merges the owner-scoped proven-safe delivery boundaries
    /// in a single `ModelContext.save()`. Returns the resulting highest persisted
    /// boundary per committed conversation. If the save throws, neither the cursor
    /// nor the boundaries are durably updated (the sync page stays retryable).
    func commitAuthoritativeSyncPage(
        ownerProfileID: UUID,
        advancedRevision: Int64?,
        safeBoundaries: [UUID: MessageReceiptBoundary]
    ) async throws -> [UUID: MessageReceiptBoundary]

    /// Loads the durable pending proven-safe delivery boundaries for `ownerProfileID`.
    func loadPendingDeliveryBoundaries(
        ownerProfileID: UUID
    ) async throws -> [UUID: MessageReceiptBoundary]

    /// Clears the pending boundary for a conversation only when the persisted
    /// boundary is `<=` the acknowledged `boundary`. A strictly higher persisted
    /// boundary is retained so a later trailing ACK still recovers after restart.
    func clearPendingDeliveryBoundary(
        ownerProfileID: UUID,
        conversationID: UUID,
        through boundary: MessageReceiptBoundary
    ) async throws

    /// Clears every pending boundary belonging to `ownerProfileID`.
    func clearPendingDeliveryBoundaries(
        ownerProfileID: UUID
    ) async throws

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
    func clearAllConfirmedMediaCacheMetadata() async throws
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

/// Narrow persistence surface used by `ConversationDeliveryAckCoordinator` for
/// cold-start bootstrap and post-ACK cleanup, so the coordinator stays decoupled
/// from the full messenger local-store protocol and is easily faked in tests.
@MainActor
protocol ConversationDeliveryAckBoundaryStore: AnyObject {
    func loadPendingDeliveryBoundaries(
        ownerProfileID: UUID
    ) async throws -> [UUID: MessageReceiptBoundary]

    func clearPendingDeliveryBoundary(
        ownerProfileID: UUID,
        conversationID: UUID,
        through boundary: MessageReceiptBoundary
    ) async throws

    func clearPendingDeliveryBoundaries(
        ownerProfileID: UUID
    ) async throws
}
