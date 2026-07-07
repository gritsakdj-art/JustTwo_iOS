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

        let tombstoneDate = deletedAt ?? Date()
        existing.deletedAt = tombstoneDate
        existing.body = nil
        existing.localState = LocalMessengerMessageState.deleted.rawValue
        existing.localUpdatedAt = tombstoneDate

        try deleteAttachments(messageID: id, context: context)
        try deleteReactionAggregates(messageID: id, context: context)
        try context.save()
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
        try deleteAttachments(messageID: messageID, context: context)

        let mapped = MessengerLocalMapping.mapAttachments(from: dto, syncedAt: syncedAt)
        for attachment in mapped {
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
}

enum MessengerLocalStoreError: Error, Equatable {
    case conversationMismatch
    case mappingFailed
    case storeUnavailable
    case staleSession
}
