import Foundation
import SwiftData

@MainActor
final class MessengerLocalStore: MessengerLocalStoreProtocol, ConversationDeliveryAckBoundaryStore {
    private static var configuredShared: MessengerLocalStore?

    static var shared: MessengerLocalStore {
        if let configuredShared {
            return configuredShared
        }
        let fallback = MessengerLocalStore(inMemoryOnly: false)
        configuredShared = fallback
        return fallback
    }

    static func configureShared(modelContainer: ModelContainer) {
        configuredShared = MessengerLocalStore(modelContainer: modelContainer)
    }

    private let backingStore: any MessengerLocalStoreProtocol
    private var sessionGeneration = 0
    private var isResetInFlight = false

    internal var sessionGenerationForTests: Int {
        sessionGeneration
    }

    var currentSessionGeneration: Int {
        sessionGeneration
    }

    var isResetInFlightPublic: Bool {
        isResetInFlight
    }

    private var conversationUpsertChain: Task<Void, Error>?

    /// Test-only hook: suspends reset after `isResetInFlight` is set so concurrent access can be verified.
    internal var testingSuspendResetAfterLock = false
    internal var testingOnResetSuspended: (() -> Void)?
    private var testingResumeReset: CheckedContinuation<Void, Never>?

    internal func testingResumeSuspendedResetForTests() {
        testingResumeReset?.resume()
        testingResumeReset = nil
        testingSuspendResetAfterLock = false
        testingOnResetSuspended = nil
    }

    internal var testingSuspendUpsertBeforeWrite = false
    internal var testingOnUpsertSuspended: (() -> Void)?
    private var testingResumeUpsert: CheckedContinuation<Void, Never>?

    internal func testingResumeSuspendedUpsertForTests() {
        testingResumeUpsert?.resume()
        testingResumeUpsert = nil
        testingSuspendUpsertBeforeWrite = false
        testingOnUpsertSuspended = nil
    }

    /// When > 0, the next N `commitAuthoritativeSyncPage` calls throw before writing.
    internal var testingCommitAuthoritativeSyncPageFailuresRemaining = 0

    internal var testingSuspendCommitBeforeWrite = false
    internal var testingOnCommitSuspended: (() -> Void)?
    private var testingResumeCommit: CheckedContinuation<Void, Never>?

    internal func testingResumeSuspendedCommitForTests() {
        testingResumeCommit?.resume()
        testingResumeCommit = nil
        testingSuspendCommitBeforeWrite = false
        testingOnCommitSuspended = nil
    }

    init(
        modelContainer: ModelContainer? = nil,
        inMemoryOnly: Bool = false,
        emitInitializationDiagnostic: Bool = true
    ) {
        let container: ModelContainer
        if let modelContainer {
            container = modelContainer
        } else {
            container = try! MessengerPersistence.makeModelContainer(inMemoryOnly: inMemoryOnly)
        }

        self.backingStore = SwiftDataMessengerLocalStore(modelContainer: container)

        if emitInitializationDiagnostic {
            MessengerDiagnostics.event(
                .messengerLocalStoreInitialized,
                metadata: [
                    "entityCount": "\(MessengerPersistence.messengerModelTypes().count)",
                    "inMemory": inMemoryOnly ? "true" : "false"
                ]
            )
        }
    }

    func resetAllMessengerData() async throws {
        sessionGeneration += 1
        let resetGeneration = sessionGeneration
        isResetInFlight = true
        MessengerDiagnostics.event(
            .messengerLocalStoreResetStarted,
            metadata: ["sessionGeneration": "\(resetGeneration)"]
        )

        if testingSuspendResetAfterLock {
            testingOnResetSuspended?()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                testingResumeReset = continuation
            }
        }

        let startedAt = Date()
        defer {
            if resetGeneration == sessionGeneration {
                isResetInFlight = false
            }
        }

        do {
            try await backingStore.resetAllMessengerData()
            guard resetGeneration == sessionGeneration else {
                MessengerDiagnostics.event(
                    .messengerLocalStoreResetFailed,
                    metadata: [
                        "errorCategory": "staleSession",
                        "sessionGeneration": "\(resetGeneration)",
                        "durationMs": "\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
                    ]
                )
                return
            }

            MessengerDiagnostics.event(
                .messengerLocalStoreResetSucceeded,
                metadata: [
                    "sessionGeneration": "\(resetGeneration)",
                    "durationMs": "\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
                ]
            )
        } catch {
            guard resetGeneration == sessionGeneration else { return }

            MessengerDiagnostics.event(
                .messengerLocalStoreResetFailed,
                metadata: [
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "sessionGeneration": "\(resetGeneration)",
                    "durationMs": "\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
                ]
            )
            throw error
        }
    }

    func upsertConversations(_ conversations: [ConversationDTO]) async throws {
        let startedAt = Date()
        try await performSessionBoundOperation(operation: "upsertConversations", isCacheWrite: true) {
            try await self.serializedConversationUpsert(conversations)
        }
        MessengerDiagnostics.event(
            .messengerLocalConversationUpserted,
            metadata: [
                "count": "\(conversations.count)",
                "durationMs": "\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
            ]
        )
    }

    private func serializedConversationUpsert(_ conversations: [ConversationDTO]) async throws {
        let capturedGeneration = sessionGeneration
        let previous = conversationUpsertChain
        let task = Task<Void, Error> {
            if let previous {
                _ = try? await previous.value
            }
            try self.validateSessionGeneration(
                capturedGeneration,
                operation: "upsertConversations",
                isCacheWrite: true
            )
            if self.testingSuspendUpsertBeforeWrite {
                self.testingOnUpsertSuspended?()
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.testingResumeUpsert = continuation
                }
            }
            try self.validateSessionGeneration(
                capturedGeneration,
                operation: "upsertConversations",
                isCacheWrite: true
            )
            try await self.backingStore.upsertConversations(conversations)
        }
        conversationUpsertChain = task
        try await task.value
    }

    func fetchLocalConversations() async throws -> [LocalConversationSnapshot] {
        try await performSessionBoundOperation(operation: "fetchLocalConversations") {
            try await backingStore.fetchLocalConversations()
        }
    }

    func patchConversationFromMessage(_ message: MessageDTO, unreadCount: Int?) async throws {
        try await performSessionBoundOperation(operation: "patchConversationFromMessage") {
            try await backingStore.patchConversationFromMessage(message, unreadCount: unreadCount)
        }
    }

    func patchConversationActivity(
        conversationID: UUID,
        lastMessageAt: Date?,
        unreadCount: Int?
    ) async throws {
        try await performSessionBoundOperation(operation: "patchConversationActivity") {
            try await backingStore.patchConversationActivity(
                conversationID: conversationID,
                lastMessageAt: lastMessageAt,
                unreadCount: unreadCount
            )
        }
    }

    func patchConversationOutgoingDeliveryStatus(
        conversationID: UUID,
        deliveryStatus: MessageDeliveryStatus
    ) async throws {
        try await performSessionBoundOperation(operation: "patchConversationOutgoingDeliveryStatus") {
            try await backingStore.patchConversationOutgoingDeliveryStatus(
                conversationID: conversationID,
                deliveryStatus: deliveryStatus
            )
        }
    }

    func upsertLastMessageSnapshot(_ message: MessageDTO) async throws {
        try await performSessionBoundOperation(operation: "upsertLastMessageSnapshot") {
            try await backingStore.upsertLastMessageSnapshot(message)
        }
    }

    func upsertMessages(
        _ messages: [MessageDTO],
        conversationID: UUID
    ) async throws {
        let startedAt = Date()
        let attachmentCount = messages.reduce(0) { $0 + ($1.deletedAt == nil ? $1.attachments.count : 0) }

        try await performSessionBoundOperation(operation: "upsertMessages") {
            try await backingStore.upsertMessages(
                messages,
                conversationID: conversationID
            )
        }
        MessengerDiagnostics.event(
            .messengerLocalMessagesUpserted,
            conversationID: conversationID,
            metadata: [
                "count": "\(messages.count)",
                "attachmentCount": "\(attachmentCount)",
                "durationMs": "\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
            ]
        )
    }

    func fetchLocalMessages(
        conversationID: UUID,
        limit: Int,
        before: Date?
    ) async throws -> [LocalMessageSnapshot] {
        try await performSessionBoundOperation(operation: "fetchLocalMessages") {
            try await backingStore.fetchLocalMessages(
                conversationID: conversationID,
                limit: limit,
                before: before
            )
        }
    }

    func markMessageDeleted(messageID: UUID, deletedAt: Date?) async throws {
        try await performSessionBoundOperation(operation: "markMessageDeleted") {
            try await backingStore.markMessageDeleted(messageID: messageID, deletedAt: deletedAt)
        }
        MessengerDiagnostics.event(
            .messengerLocalMessageDeleted,
            messageID: messageID,
            metadata: [
                "hasDeletedAt": deletedAt == nil ? "false" : "true"
            ]
        )
    }

    func upsertReactions(from message: MessageDTO) async throws {
        try await performSessionBoundOperation(operation: "upsertReactions") {
            try await backingStore.upsertReactions(from: message)
        }
    }

    func applyReceipt(_ receipt: MessengerReceiptDTO) async throws {
        try await performSessionBoundOperation(operation: "applyReceipt") {
            try await backingStore.applyReceipt(receipt)
        }
        MessengerDiagnostics.event(
            .messengerLocalReceiptApplied,
            conversationID: receipt.conversationID,
            messageID: receipt.messageID,
            metadata: [
                "hasDeliveredAt": receipt.deliveredAt == nil ? "false" : "true",
                "hasReadAt": receipt.readAt == nil ? "false" : "true"
            ]
        )
    }

    func applyRealtimeReceipt(
        ownerProfileID: UUID,
        conversationID: UUID,
        participantProfileID: UUID,
        kind: MessengerReceiptKind,
        boundaryMessageID: UUID
    ) async throws -> MessengerReceiptApplyResult {
        try await performSessionBoundOperation(operation: "applyRealtimeReceipt") {
            try await backingStore.applyRealtimeReceipt(
                ownerProfileID: ownerProfileID,
                conversationID: conversationID,
                participantProfileID: participantProfileID,
                kind: kind,
                boundaryMessageID: boundaryMessageID
            )
        }
    }

    func upsertSyncMetadata(_ metadata: LocalMessengerSyncMetadataSnapshot) async throws {
        try await performSessionBoundOperation(operation: "upsertSyncMetadata") {
            try await backingStore.upsertSyncMetadata(metadata)
        }
        MessengerDiagnostics.event(
            .messengerLocalSyncMetadataUpdated,
            metadata: [
                "revision": metadata.lastAppliedRevision.map(String.init) ?? "nil",
                "schemaVersion": "\(metadata.schemaVersion)"
            ]
        )
    }

    func fetchSyncMetadata() async throws -> LocalMessengerSyncMetadataSnapshot? {
        try await performSessionBoundOperation(operation: "fetchSyncMetadata") {
            try await backingStore.fetchSyncMetadata()
        }
    }

    func commitAuthoritativeSyncPage(
        ownerProfileID: UUID,
        advancedRevision: Int64?,
        safeBoundaries: [UUID: MessageReceiptBoundary]
    ) async throws -> [UUID: MessageReceiptBoundary] {
        try await performSessionBoundOperation(operation: "commitAuthoritativeSyncPage", isCacheWrite: true) {
            let operationGeneration = self.sessionGeneration
            if self.testingCommitAuthoritativeSyncPageFailuresRemaining > 0 {
                self.testingCommitAuthoritativeSyncPageFailuresRemaining -= 1
                throw MessengerLocalStoreError.storeUnavailable
            }
            if self.testingSuspendCommitBeforeWrite {
                self.testingOnCommitSuspended?()
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.testingResumeCommit = continuation
                }
            }
            try self.validateSessionGeneration(
                operationGeneration,
                operation: "commitAuthoritativeSyncPage",
                isCacheWrite: true
            )
            return try await self.backingStore.commitAuthoritativeSyncPage(
                ownerProfileID: ownerProfileID,
                advancedRevision: advancedRevision,
                safeBoundaries: safeBoundaries
            )
        }
    }

    func loadPendingDeliveryBoundaries(
        ownerProfileID: UUID
    ) async throws -> [UUID: MessageReceiptBoundary] {
        try await performSessionBoundOperation(operation: "loadPendingDeliveryBoundaries") {
            try await backingStore.loadPendingDeliveryBoundaries(ownerProfileID: ownerProfileID)
        }
    }

    func clearPendingDeliveryBoundary(
        ownerProfileID: UUID,
        conversationID: UUID,
        through boundary: MessageReceiptBoundary
    ) async throws {
        try await performSessionBoundOperation(operation: "clearPendingDeliveryBoundary", isCacheWrite: true) {
            try await backingStore.clearPendingDeliveryBoundary(
                ownerProfileID: ownerProfileID,
                conversationID: conversationID,
                through: boundary
            )
        }
    }

    func clearPendingDeliveryBoundaries(
        ownerProfileID: UUID
    ) async throws {
        try await performSessionBoundOperation(operation: "clearPendingDeliveryBoundaries", isCacheWrite: true) {
            try await backingStore.clearPendingDeliveryBoundaries(ownerProfileID: ownerProfileID)
        }
    }

    func updateAttachmentMediaCacheMetadata(
        attachmentID: String,
        variant: MessengerMediaVariant,
        byteSize: Int,
        cachedAt: Date
    ) async throws {
        try await performSessionBoundOperation(operation: "updateAttachmentMediaCacheMetadata") {
            try await backingStore.updateAttachmentMediaCacheMetadata(
                attachmentID: attachmentID,
                variant: variant,
                byteSize: byteSize,
                cachedAt: cachedAt
            )
        }
    }

    func recordAttachmentMediaAccess(
        attachmentID: String,
        variant: MessengerMediaVariant,
        accessedAt: Date
    ) async throws {
        try await performSessionBoundOperation(operation: "recordAttachmentMediaAccess") {
            try await backingStore.recordAttachmentMediaAccess(
                attachmentID: attachmentID,
                variant: variant,
                accessedAt: accessedAt
            )
        }
    }

    func clearAttachmentMediaCacheMetadata(attachmentID: String) async throws {
        try await performSessionBoundOperation(operation: "clearAttachmentMediaCacheMetadata") {
            try await backingStore.clearAttachmentMediaCacheMetadata(attachmentID: attachmentID)
        }
    }

    func clearAllConfirmedMediaCacheMetadata() async throws {
        try await performSessionBoundOperation(operation: "clearAllConfirmedMediaCacheMetadata") {
            try await backingStore.clearAllConfirmedMediaCacheMetadata()
        }
    }

    func fetchAttachmentLocalCacheKeys() async throws -> Set<String> {
        try await performSessionBoundOperation(operation: "fetchAttachmentLocalCacheKeys") {
            try await backingStore.fetchAttachmentLocalCacheKeys()
        }
    }

    func createTextOutboxItem(
        conversationID: UUID,
        clientMessageID: String,
        body: String,
        replyToMessageID: UUID?
    ) async throws -> MessengerOutboxItemSnapshot {
        try await performSessionBoundOperation(operation: "createTextOutboxItem") {
            try await backingStore.createTextOutboxItem(
                conversationID: conversationID,
                clientMessageID: clientMessageID,
                body: body,
                replyToMessageID: replyToMessageID
            )
        }
    }

    func fetchPendingOutboxItems() async throws -> [MessengerOutboxItemSnapshot] {
        try await performSessionBoundOperation(operation: "fetchPendingOutboxItems") {
            try await backingStore.fetchPendingOutboxItems()
        }
    }

    func fetchOutboxItems(conversationID: UUID) async throws -> [MessengerOutboxItemSnapshot] {
        try await performSessionBoundOperation(operation: "fetchOutboxItems") {
            try await backingStore.fetchOutboxItems(conversationID: conversationID)
        }
    }

    func fetchOutboxItem(clientMessageID: String) async throws -> MessengerOutboxItemSnapshot? {
        try await performSessionBoundOperation(operation: "fetchOutboxItem") {
            try await backingStore.fetchOutboxItem(clientMessageID: clientMessageID)
        }
    }

    func markOutboxSending(clientMessageID: String) async throws {
        try await performSessionBoundOperation(operation: "markOutboxSending") {
            try await backingStore.markOutboxSending(clientMessageID: clientMessageID)
        }
    }

    func markOutboxFailed(
        clientMessageID: String,
        errorCode: String?,
        nextRetryAt: Date?
    ) async throws {
        try await performSessionBoundOperation(operation: "markOutboxFailed") {
            try await backingStore.markOutboxFailed(
                clientMessageID: clientMessageID,
                errorCode: errorCode,
                nextRetryAt: nextRetryAt
            )
        }
    }

    func markOutboxPending(clientMessageID: String) async throws {
        try await performSessionBoundOperation(operation: "markOutboxPending") {
            try await backingStore.markOutboxPending(clientMessageID: clientMessageID)
        }
    }

    func markOutboxSent(clientMessageID: String, serverMessageID: UUID) async throws {
        try await performSessionBoundOperation(operation: "markOutboxSent") {
            try await backingStore.markOutboxSent(
                clientMessageID: clientMessageID,
                serverMessageID: serverMessageID
            )
        }
    }

    func deleteOutboxItem(clientMessageID: String) async throws {
        try await performSessionBoundOperation(operation: "deleteOutboxItem") {
            try await backingStore.deleteOutboxItem(clientMessageID: clientMessageID)
        }
    }

    func deleteOutboxItems(conversationID: UUID) async throws {
        try await performSessionBoundOperation(operation: "deleteOutboxItems") {
            try await backingStore.deleteOutboxItems(conversationID: conversationID)
        }
    }

    func resetStaleOutboxSendingItems() async throws -> Int {
        try await performSessionBoundOperation(operation: "resetStaleOutboxSendingItems") {
            try await backingStore.resetStaleOutboxSendingItems()
        }
    }

    func clearOutbox() async throws {
        try await performSessionBoundOperation(operation: "clearOutbox") {
            try await backingStore.clearOutbox()
        }
    }

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
    ) async throws -> MessengerOutboxItemSnapshot {
        try await performSessionBoundOperation(operation: "createImageOutboxItem") {
            try await backingStore.createImageOutboxItem(
                conversationID: conversationID,
                clientMessageID: clientMessageID,
                caption: caption,
                replyToMessageID: replyToMessageID,
                pendingMediaID: pendingMediaID,
                localRelativePath: localRelativePath,
                contentType: contentType,
                byteSize: byteSize,
                width: width,
                height: height
            )
        }
    }

    func fetchPendingMedia(clientMessageID: String) async throws -> MessengerPendingMediaSnapshot? {
        try await performSessionBoundOperation(operation: "fetchPendingMedia") {
            try await backingStore.fetchPendingMedia(clientMessageID: clientMessageID)
        }
    }

    func fetchPendingMedia(pendingMediaID: String) async throws -> MessengerPendingMediaSnapshot? {
        try await performSessionBoundOperation(operation: "fetchPendingMediaByID") {
            try await backingStore.fetchPendingMedia(pendingMediaID: pendingMediaID)
        }
    }

    func deletePendingMedia(clientMessageID: String) async throws {
        try await performSessionBoundOperation(operation: "deletePendingMedia") {
            try await backingStore.deletePendingMedia(clientMessageID: clientMessageID)
        }
    }

    func clearPendingMedia() async throws {
        try await performSessionBoundOperation(operation: "clearPendingMedia") {
            try await backingStore.clearPendingMedia()
        }
    }

    func fetchPendingMediaRelativePaths() async throws -> Set<String> {
        try await performSessionBoundOperation(operation: "fetchPendingMediaRelativePaths") {
            try await backingStore.fetchPendingMediaRelativePaths()
        }
    }

    private func performSessionBoundOperation<T>(
        operation: String,
        isCacheWrite: Bool = false,
        _ work: () async throws -> T
    ) async throws -> T {
        guard !isResetInFlight else {
            if isCacheWrite {
                logCacheWriteIgnored(reason: "resetInFlight", operation: operation, capturedGeneration: sessionGeneration)
            }
            throw MessengerLocalStoreError.storeUnavailable
        }

        let generation = sessionGeneration
        do {
            try validateSessionGeneration(generation, operation: operation, isCacheWrite: isCacheWrite)
            let value = try await work()
            try validateSessionGeneration(generation, operation: operation, isCacheWrite: isCacheWrite)
            return value
        } catch let error as MessengerLocalStoreError {
            throw error
        } catch {
            MessengerDiagnostics.event(
                .messengerLocalMappingFailed,
                metadata: [
                    "operation": operation,
                    "errorCategory": MessengerDiagnostics.sanitizeError(error)
                ]
            )
            throw error
        }
    }

    private func validateSessionGeneration(
        _ generation: Int,
        operation: String,
        isCacheWrite: Bool
    ) throws {
        guard generation == sessionGeneration, !isResetInFlight else {
            if isCacheWrite {
                logCacheWriteIgnored(reason: "staleSession", operation: operation, capturedGeneration: generation)
            } else {
                MessengerDiagnostics.event(
                    .messengerLocalMappingFailed,
                    metadata: [
                        "operation": operation,
                        "errorCategory": "staleSession",
                        "sessionGeneration": "\(generation)"
                    ]
                )
            }
            throw MessengerLocalStoreError.staleSession
        }
    }

    private func logCacheWriteIgnored(
        reason: String,
        operation: String,
        capturedGeneration: Int
    ) {
        MessengerDiagnostics.event(
            .presenceCacheWriteIgnored,
            metadata: [
                "reason": reason,
                "operation": operation,
                "source": "localStore",
                "capturedSessionGeneration": "\(capturedGeneration)",
                "currentSessionGeneration": "\(sessionGeneration)",
                "hasAccountMismatch": "false"
            ]
        )
    }
}

enum MessengerLocalStorageFeatureFlags {
    /// PR15C: per-conversation message history reads from local DB.
    static let isLocalReadEnabled = true
    /// PR15B enables cached conversation list hydration and persistence.
    static let isCachedConversationListEnabled = true
}
