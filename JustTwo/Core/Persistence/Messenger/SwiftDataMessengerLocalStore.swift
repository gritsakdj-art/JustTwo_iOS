import Foundation
import SwiftData

@MainActor
final class SwiftDataMessengerLocalStore: MessengerLocalStoreProtocol {
    private let modelContainer: ModelContainer
    private var modelContext: ModelContext {
        ModelContext(modelContainer)
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func resetAllMessengerData() async throws {
        let context = modelContext

        for modelType in MessengerPersistence.messengerModelTypes() {
            try context.delete(model: modelType)
        }

        try context.save()
    }

    func upsertConversations(_ conversations: [ConversationDTO]) async throws {
        let context = modelContext
        let syncedAt = Date()

        for dto in conversations {
            let mapped = MessengerLocalMapping.mapConversation(from: dto, syncedAt: syncedAt)
            let id = mapped.id

            if let existing = try fetchConversationEntity(id: id, context: context) {
                MessengerLocalMapping.applyConversation(mapped, to: existing)
            } else {
                context.insert(mapped)
            }
        }

        try context.save()
    }

    func fetchLocalConversations() async throws -> [LocalConversationSnapshot] {
        let context = modelContext
        let descriptor = FetchDescriptor<LocalMessengerConversation>(
            sortBy: [
                SortDescriptor(\.lastMessageAt, order: .reverse),
                SortDescriptor(\.localUpdatedAt, order: .reverse)
            ]
        )

        return try context.fetch(descriptor).map(MessengerLocalMapping.conversationSnapshot(from:))
    }

    func patchConversationFromMessage(_ message: MessageDTO, unreadCount: Int?) async throws {
        let context = modelContext
        let syncedAt = Date()
        let conversationKey = message.conversationID.uuidString

        guard let existing = try fetchConversationEntity(id: conversationKey, context: context) else {
            return
        }

        MessengerLocalMapping.applyLastMessage(from: message, to: existing, syncedAt: syncedAt)
        if let unreadCount {
            existing.unreadCount = unreadCount
        }
        existing.lastMessageAt = message.createdAt ?? existing.lastMessageAt
        existing.localUpdatedAt = syncedAt
        try context.save()
    }

    func patchConversationActivity(
        conversationID: UUID,
        lastMessageAt: Date?,
        unreadCount: Int?
    ) async throws {
        let context = modelContext
        let syncedAt = Date()
        let conversationKey = conversationID.uuidString

        guard let existing = try fetchConversationEntity(id: conversationKey, context: context) else {
            return
        }

        if let lastMessageAt {
            existing.lastMessageAt = lastMessageAt
        }
        if let unreadCount {
            existing.unreadCount = unreadCount
        }
        existing.localUpdatedAt = syncedAt
        try context.save()
    }

    func upsertLastMessageSnapshot(_ message: MessageDTO) async throws {
        try await upsertMessages([message], conversationID: message.conversationID)
    }

    func upsertMessages(
        _ messages: [MessageDTO],
        conversationID: UUID
    ) async throws {
        let context = modelContext
        let syncedAt = Date()

        for dto in messages {
            try upsertMessage(
                dto,
                expectedConversationID: conversationID,
                syncedAt: syncedAt,
                context: context
            )
        }

        try context.save()
    }

    func fetchLocalMessages(
        conversationID: UUID,
        limit: Int,
        before: Date?
    ) async throws -> [LocalMessageSnapshot] {
        let context = modelContext
        let conversationKey = conversationID.uuidString

        var descriptor = FetchDescriptor<LocalMessengerMessage>(
            predicate: #Predicate { message in
                message.conversationID == conversationKey
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(1, limit)

        let entities = try context.fetch(descriptor)
        let filtered = before.map { cutoff in
            entities.filter { $0.createdAt < cutoff }
        } ?? entities

        return try filtered.map { entity in
            let attachments = try fetchAttachmentSnapshots(messageID: entity.id, context: context)
            let reactions = try fetchReactionAggregateSnapshots(messageID: entity.id, context: context)
            return MessengerLocalMapping.messageSnapshot(
                from: entity,
                attachments: attachments,
                reactions: reactions
            )
        }
    }

    func markMessageDeleted(messageID: UUID, deletedAt: Date?) async throws {
        let context = modelContext
        let id = messageID.uuidString
        guard let existing = try fetchMessageEntity(id: id, context: context) else { return }

        let attachmentSnapshots = try fetchAttachmentSnapshots(messageID: id, context: context)
        let attachmentIDs = attachmentSnapshots.map { $0.localCacheKey ?? $0.id }

        let tombstoneDate = deletedAt ?? Date()
        existing.deletedAt = tombstoneDate
        existing.body = nil
        existing.localState = LocalMessengerMessageState.deleted.rawValue
        existing.localUpdatedAt = tombstoneDate

        try deleteAttachments(messageID: id, context: context)
        try deleteReactionAggregates(messageID: id, context: context)
        try context.save()

        for attachmentID in attachmentIDs {
            await MessengerMediaCacheService.removeMedia(attachmentID: attachmentID)
        }
    }

    func upsertReactions(from message: MessageDTO) async throws {
        let context = modelContext
        let syncedAt = Date()
        let messageID = message.id.uuidString

        try deleteReactionAggregates(messageID: messageID, context: context)

        let mapped = MessengerLocalMapping.mapReactionAggregates(from: message, syncedAt: syncedAt)
        for reaction in mapped {
            context.insert(reaction)
        }

        try context.save()
    }

    func applyReceipt(_ receipt: MessengerReceiptDTO) async throws {
        let context = modelContext
        let syncedAt = Date()
        let mapped = MessengerLocalMapping.mapReceipt(from: receipt, syncedAt: syncedAt)
        let id = mapped.id

        if let existing = try fetchReceiptEntity(id: id, context: context) {
            MessengerLocalMapping.applyReceipt(mapped, to: existing)
        } else {
            context.insert(mapped)
        }

        try context.save()
    }

    func upsertSyncMetadata(_ metadata: LocalMessengerSyncMetadataSnapshot) async throws {
        let context = modelContext
        let syncedAt = Date()
        let mapped = MessengerLocalMapping.mapSyncMetadata(from: metadata, syncedAt: syncedAt)

        if let existing = try fetchSyncMetadataEntity(id: mapped.id, context: context) {
            if let incomingRevision = mapped.lastAppliedRevision,
               let currentRevision = existing.lastAppliedRevision,
               incomingRevision < currentRevision {
                existing.lastSuccessfulSyncAt = mapped.lastSuccessfulSyncAt ?? existing.lastSuccessfulSyncAt
                existing.lastFullRefreshAt = mapped.lastFullRefreshAt ?? existing.lastFullRefreshAt
                existing.localUpdatedAt = syncedAt
            } else {
                existing.lastAppliedRevision = mapped.lastAppliedRevision ?? existing.lastAppliedRevision
                existing.lastSuccessfulSyncAt = mapped.lastSuccessfulSyncAt ?? existing.lastSuccessfulSyncAt
                existing.lastFullRefreshAt = mapped.lastFullRefreshAt ?? existing.lastFullRefreshAt
                existing.schemaVersion = mapped.schemaVersion
                existing.localUpdatedAt = syncedAt
            }
        } else {
            context.insert(mapped)
        }

        try context.save()
    }

    func fetchSyncMetadata() async throws -> LocalMessengerSyncMetadataSnapshot? {
        let context = modelContext
        guard let entity = try fetchSyncMetadataEntity(
            id: MessengerPersistence.syncMetadataGlobalID,
            context: context
        ) else {
            return nil
        }

        return MessengerLocalMapping.syncMetadataSnapshot(from: entity)
    }

    func updateAttachmentMediaCacheMetadata(
        attachmentID: String,
        variant: MessengerMediaVariant,
        byteSize: Int,
        cachedAt: Date
    ) async throws {
        let context = modelContext
        guard let attachment = try fetchAttachmentEntity(id: attachmentID, context: context) else {
            return
        }

        switch variant {
        case .thumbnail:
            attachment.hasLocalThumbnail = true
            attachment.localThumbnailByteSize = byteSize
        case .full:
            attachment.hasLocalFullImage = true
            attachment.localFullByteSize = byteSize
        }

        attachment.mediaCachedAt = attachment.mediaCachedAt ?? cachedAt
        attachment.mediaLastAccessedAt = cachedAt
        attachment.localUpdatedAt = cachedAt
        try context.save()
    }

    func recordAttachmentMediaAccess(
        attachmentID: String,
        variant: MessengerMediaVariant,
        accessedAt: Date
    ) async throws {
        let context = modelContext
        guard let attachment = try fetchAttachmentEntity(id: attachmentID, context: context) else {
            return
        }

        attachment.mediaLastAccessedAt = accessedAt
        attachment.localUpdatedAt = accessedAt
        try context.save()
    }

    func clearAttachmentMediaCacheMetadata(attachmentID: String) async throws {
        let context = modelContext
        guard let attachment = try fetchAttachmentEntity(id: attachmentID, context: context) else {
            return
        }

        attachment.hasLocalThumbnail = false
        attachment.hasLocalFullImage = false
        attachment.localThumbnailByteSize = nil
        attachment.localFullByteSize = nil
        attachment.mediaCachedAt = nil
        attachment.mediaLastAccessedAt = nil
        attachment.localUpdatedAt = Date()
        try context.save()
    }

    func fetchAttachmentLocalCacheKeys() async throws -> Set<String> {
        let context = modelContext
        let descriptor = FetchDescriptor<LocalMessengerAttachment>()
        let attachments = try context.fetch(descriptor)
        return Set(attachments.compactMap { $0.localCacheKey ?? $0.id })
    }

    func createTextOutboxItem(
        conversationID: UUID,
        clientMessageID: String,
        body: String,
        replyToMessageID: UUID?
    ) async throws -> MessengerOutboxItemSnapshot {
        let context = modelContext
        let now = Date()

        if let existing = try fetchOutboxEntity(clientMessageID: clientMessageID, context: context) {
            return MessengerLocalMapping.outboxSnapshot(from: existing)
        }

        let mapped = MessengerLocalMapping.mapOutboxItem(
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            body: body,
            replyToMessageID: replyToMessageID,
            status: .pending,
            attemptCount: 0,
            lastErrorCode: nil,
            nextRetryAt: now,
            createdAt: now,
            updatedAt: now,
            lastAttemptAt: nil,
            serverMessageID: nil
        )
        context.insert(mapped)
        try context.save()
        return MessengerLocalMapping.outboxSnapshot(from: mapped)
    }

    func fetchPendingOutboxItems() async throws -> [MessengerOutboxItemSnapshot] {
        let context = modelContext
        let now = Date()
        let pendingStatus = MessengerOutboxItemStatus.pending.rawValue
        let failedStatus = MessengerOutboxItemStatus.failed.rawValue
        let sendingStatus = MessengerOutboxItemStatus.sending.rawValue

        let descriptor = FetchDescriptor<LocalMessengerOutboxItem>(
            predicate: #Predicate { item in
                item.status == pendingStatus
                    || item.status == failedStatus
                    || item.status == sendingStatus
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        return try context.fetch(descriptor)
            .map(MessengerLocalMapping.outboxSnapshot(from:))
            .filter { snapshot in
                switch snapshot.status {
                case .pending, .sending:
                    return true
                case .failed:
                    guard let nextRetryAt = snapshot.nextRetryAt else { return true }
                    return nextRetryAt <= now
                case .sent, .cancelled:
                    return false
                }
            }
    }

    func fetchOutboxItems(conversationID: UUID) async throws -> [MessengerOutboxItemSnapshot] {
        let context = modelContext
        let conversationKey = conversationID.uuidString
        let descriptor = FetchDescriptor<LocalMessengerOutboxItem>(
            predicate: #Predicate { $0.conversationID == conversationKey },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor).map(MessengerLocalMapping.outboxSnapshot(from:))
    }

    func fetchOutboxItem(clientMessageID: String) async throws -> MessengerOutboxItemSnapshot? {
        let context = modelContext
        guard let entity = try fetchOutboxEntity(clientMessageID: clientMessageID, context: context) else {
            return nil
        }
        return MessengerLocalMapping.outboxSnapshot(from: entity)
    }

    func markOutboxSending(clientMessageID: String) async throws {
        let context = modelContext
        guard let entity = try fetchOutboxEntity(clientMessageID: clientMessageID, context: context) else {
            return
        }
        let now = Date()
        entity.status = MessengerOutboxItemStatus.sending.rawValue
        entity.lastAttemptAt = now
        entity.updatedAt = now
        try context.save()
    }

    func markOutboxFailed(
        clientMessageID: String,
        errorCode: String?,
        nextRetryAt: Date?
    ) async throws {
        let context = modelContext
        guard let entity = try fetchOutboxEntity(clientMessageID: clientMessageID, context: context) else {
            return
        }
        let now = Date()
        entity.attemptCount += 1
        entity.status = MessengerOutboxItemStatus.failed.rawValue
        entity.lastErrorCode = errorCode
        entity.nextRetryAt = nextRetryAt ?? MessengerOutboxRetryPolicy.nextRetryDate(
            afterAttemptCount: entity.attemptCount,
            from: now
        )
        entity.updatedAt = now
        try context.save()
    }

    func markOutboxPending(clientMessageID: String) async throws {
        let context = modelContext
        guard let entity = try fetchOutboxEntity(clientMessageID: clientMessageID, context: context) else {
            return
        }
        let now = Date()
        entity.status = MessengerOutboxItemStatus.pending.rawValue
        entity.nextRetryAt = now
        entity.updatedAt = now
        try context.save()
    }

    func markOutboxSent(clientMessageID: String, serverMessageID: UUID) async throws {
        let context = modelContext
        guard let entity = try fetchOutboxEntity(clientMessageID: clientMessageID, context: context) else {
            return
        }
        let now = Date()
        entity.status = MessengerOutboxItemStatus.sent.rawValue
        entity.serverMessageID = serverMessageID.uuidString
        entity.updatedAt = now
        try context.save()
    }

    func deleteOutboxItem(clientMessageID: String) async throws {
        let context = modelContext
        guard let entity = try fetchOutboxEntity(clientMessageID: clientMessageID, context: context) else {
            return
        }
        context.delete(entity)
        try context.save()
    }

    func deleteOutboxItems(conversationID: UUID) async throws {
        let context = modelContext
        let conversationKey = conversationID.uuidString
        let descriptor = FetchDescriptor<LocalMessengerOutboxItem>(
            predicate: #Predicate { $0.conversationID == conversationKey }
        )
        for entity in try context.fetch(descriptor) {
            context.delete(entity)
        }
        try context.save()
    }

    func resetStaleOutboxSendingItems() async throws -> Int {
        let context = modelContext
        let sendingStatus = MessengerOutboxItemStatus.sending.rawValue
        let descriptor = FetchDescriptor<LocalMessengerOutboxItem>(
            predicate: #Predicate { $0.status == sendingStatus }
        )
        let threshold = Date().addingTimeInterval(-MessengerOutboxRetryPolicy.staleSendingThreshold)
        var resetCount = 0
        let now = Date()

        for entity in try context.fetch(descriptor) {
            let referenceDate = entity.lastAttemptAt ?? entity.updatedAt
            guard referenceDate <= threshold else { continue }
            entity.status = MessengerOutboxItemStatus.pending.rawValue
            entity.nextRetryAt = now
            entity.updatedAt = now
            resetCount += 1
        }

        if resetCount > 0 {
            try context.save()
        }
        return resetCount
    }

    func clearOutbox() async throws {
        let context = modelContext
        try context.delete(model: LocalMessengerOutboxItem.self)
        try context.save()
    }
}

// MARK: - Private helpers

private extension SwiftDataMessengerLocalStore {
    func upsertMessage(
        _ dto: MessageDTO,
        expectedConversationID: UUID,
        syncedAt: Date,
        context: ModelContext
    ) throws {
        guard dto.conversationID == expectedConversationID else {
            throw MessengerLocalStoreError.conversationMismatch
        }

        let mapped = MessengerLocalMapping.mapMessage(from: dto, syncedAt: syncedAt)
        let target: LocalMessengerMessage

        if let existing = try fetchMessageEntity(id: mapped.id, context: context) {
            MessengerLocalMapping.applyMessage(mapped, to: existing)
            target = existing
        } else if let clientMessageID = mapped.clientMessageID,
                  let existing = try fetchMessageEntity(
                    clientMessageID: clientMessageID,
                    conversationID: mapped.conversationID,
                    context: context
                  ) {
            existing.id = mapped.id
            MessengerLocalMapping.applyMessage(mapped, to: existing)
            target = existing
        } else {
            context.insert(mapped)
            target = mapped
        }

        try replaceAttachments(for: dto, syncedAt: syncedAt, context: context)
        try replaceReactionAggregates(for: dto, syncedAt: syncedAt, context: context)

        if target.deletedAt != nil {
            try deleteAttachments(messageID: target.id, context: context)
        }
    }

    func replaceAttachments(
        for dto: MessageDTO,
        syncedAt: Date,
        context: ModelContext
    ) throws {
        let messageID = dto.id.uuidString
        let existingAttachments = try context.fetch(
            FetchDescriptor<LocalMessengerAttachment>(
                predicate: #Predicate { $0.messageID == messageID }
            )
        )
        let preservedMetadata = Dictionary(
            uniqueKeysWithValues: existingAttachments.map { ($0.id, $0) }
        )

        try deleteAttachments(messageID: messageID, context: context)

        let mapped = MessengerLocalMapping.mapAttachments(from: dto, syncedAt: syncedAt)
        for attachment in mapped {
            if let previous = preservedMetadata[attachment.id] {
                MessengerLocalMapping.applyAttachmentMediaMetadata(from: previous, to: attachment)
            }
            context.insert(attachment)
        }
    }

    func replaceReactionAggregates(
        for dto: MessageDTO,
        syncedAt: Date,
        context: ModelContext
    ) throws {
        let messageID = dto.id.uuidString
        try deleteReactionAggregates(messageID: messageID, context: context)

        let mapped = MessengerLocalMapping.mapReactionAggregates(from: dto, syncedAt: syncedAt)
        for reaction in mapped {
            context.insert(reaction)
        }
    }

    func fetchConversationEntity(id: String, context: ModelContext) throws -> LocalMessengerConversation? {
        var descriptor = FetchDescriptor<LocalMessengerConversation>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchMessageEntity(id: String, context: ModelContext) throws -> LocalMessengerMessage? {
        var descriptor = FetchDescriptor<LocalMessengerMessage>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchMessageEntity(
        clientMessageID: String,
        conversationID: String,
        context: ModelContext
    ) throws -> LocalMessengerMessage? {
        var descriptor = FetchDescriptor<LocalMessengerMessage>(
            predicate: #Predicate { message in
                message.clientMessageID == clientMessageID && message.conversationID == conversationID
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchReceiptEntity(id: String, context: ModelContext) throws -> LocalMessengerReceipt? {
        var descriptor = FetchDescriptor<LocalMessengerReceipt>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchSyncMetadataEntity(id: String, context: ModelContext) throws -> LocalMessengerSyncMetadata? {
        var descriptor = FetchDescriptor<LocalMessengerSyncMetadata>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchAttachmentSnapshots(messageID: String, context: ModelContext) throws -> [LocalAttachmentSnapshot] {
        let descriptor = FetchDescriptor<LocalMessengerAttachment>(
            predicate: #Predicate { $0.messageID == messageID }
        )
        return try context.fetch(descriptor).map(MessengerLocalMapping.attachmentSnapshot(from:))
    }

    func fetchReactionAggregateSnapshots(
        messageID: String,
        context: ModelContext
    ) throws -> [LocalReactionAggregateSnapshot] {
        let descriptor = FetchDescriptor<LocalMessengerReactionAggregate>(
            predicate: #Predicate { $0.messageID == messageID }
        )
        return try context.fetch(descriptor).map(MessengerLocalMapping.reactionAggregateSnapshot(from:))
    }

    func fetchAttachmentEntity(id: String, context: ModelContext) throws -> LocalMessengerAttachment? {
        if let exact = try fetchAttachmentEntityByID(entityID: id, context: context) {
            return exact
        }

        let normalized = id.lowercased()
        if normalized != id, let match = try fetchAttachmentEntityByID(entityID: normalized, context: context) {
            return match
        }

        var cacheKeyDescriptor = FetchDescriptor<LocalMessengerAttachment>(
            predicate: #Predicate { attachment in
                attachment.localCacheKey == id || attachment.localCacheKey == normalized
            }
        )
        cacheKeyDescriptor.fetchLimit = 1
        return try context.fetch(cacheKeyDescriptor).first
    }

    func fetchAttachmentEntityByID(entityID: String, context: ModelContext) throws -> LocalMessengerAttachment? {
        var descriptor = FetchDescriptor<LocalMessengerAttachment>(
            predicate: #Predicate { attachment in
                attachment.id == entityID
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func deleteAttachments(messageID: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<LocalMessengerAttachment>(
            predicate: #Predicate { $0.messageID == messageID }
        )
        for attachment in try context.fetch(descriptor) {
            context.delete(attachment)
        }
    }

    func deleteReactionAggregates(messageID: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<LocalMessengerReactionAggregate>(
            predicate: #Predicate { $0.messageID == messageID }
        )
        for reaction in try context.fetch(descriptor) {
            context.delete(reaction)
        }
    }

    func fetchOutboxEntity(
        clientMessageID: String,
        context: ModelContext
    ) throws -> LocalMessengerOutboxItem? {
        var descriptor = FetchDescriptor<LocalMessengerOutboxItem>(
            predicate: #Predicate { $0.clientMessageID == clientMessageID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

enum MessengerLocalStoreError: Error, Equatable {
    case conversationMismatch
    case mappingFailed
    case storeUnavailable
    case staleSession
}
