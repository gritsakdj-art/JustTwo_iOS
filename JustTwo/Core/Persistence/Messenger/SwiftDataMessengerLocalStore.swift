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
        MessengerPendingMediaStore.clearAll()
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

    func patchConversationOutgoingDeliveryStatus(
        conversationID: UUID,
        deliveryStatus: MessageDeliveryStatus
    ) async throws {
        let context = modelContext
        let syncedAt = Date()
        let conversationKey = conversationID.uuidString

        guard let existing = try fetchConversationEntity(id: conversationKey, context: context) else {
            return
        }

        let current = existing.lastMessageDeliveryStatus
            .flatMap(MessageDeliveryStatus.init(rawValue:))
        guard deliveryStatus.rank > (current?.rank ?? MessageDeliveryStatus.sent.rank) else {
            return
        }

        existing.lastMessageDeliveryStatus = deliveryStatus.rawValue
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

        let entities: [LocalMessengerMessage]
        if let cutoff = before {
            var descriptor = FetchDescriptor<LocalMessengerMessage>(
                predicate: #Predicate { message in
                    message.conversationID == conversationKey && message.createdAt < cutoff
                },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = max(1, limit)
            entities = try context.fetch(descriptor)
        } else {
            var descriptor = FetchDescriptor<LocalMessengerMessage>(
                predicate: #Predicate { message in
                    message.conversationID == conversationKey
                },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = max(1, limit)
            entities = try context.fetch(descriptor)
        }

        let messageIDs = Set(entities.map(\.id))
        let attachmentsByMessageID = try fetchAttachmentSnapshots(
            messageIDs: messageIDs,
            conversationID: conversationKey,
            context: context
        )
        let reactionsByMessageID = try fetchReactionAggregateSnapshots(
            messageIDs: messageIDs,
            conversationID: conversationKey,
            context: context
        )

        return entities.map { entity in
            MessengerLocalMapping.messageSnapshot(
                from: entity,
                attachments: attachmentsByMessageID[entity.id] ?? [],
                reactions: reactionsByMessageID[entity.id] ?? []
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

    func applyRealtimeReceipt(
        ownerProfileID: UUID,
        conversationID: UUID,
        participantProfileID: UUID,
        kind: MessengerReceiptKind,
        boundaryMessageID: UUID
    ) async throws -> MessengerReceiptApplyResult {
        let context = modelContext
        let syncedAt = Date()
        let conversationKey = conversationID.uuidString

        guard try fetchConversationEntity(id: conversationKey, context: context) != nil else {
            return .targetMissing()
        }

        guard let boundaryMessage = try fetchMessageEntity(
            id: boundaryMessageID.uuidString,
            context: context
        ) else {
            return .targetMissing()
        }

        let incomingBoundary = MessageReceiptBoundary(
            createdAt: boundaryMessage.createdAt,
            messageID: boundaryMessageID
        )

        let receiptID = MessengerLocalMapping.receiptIdentity(
            conversationID: conversationKey,
            profileID: participantProfileID.uuidString
        )

        let receiptEntity: LocalMessengerReceipt
        if let existing = try fetchReceiptEntity(id: receiptID, context: context) {
            receiptEntity = existing
        } else {
            let created = LocalMessengerReceipt(
                id: receiptID,
                conversationID: conversationKey,
                profileID: participantProfileID.uuidString,
                lastDeliveredAt: nil,
                lastReadAt: nil,
                lastDeliveredMessageID: nil,
                lastReadMessageID: nil,
                localUpdatedAt: syncedAt
            )
            context.insert(created)
            receiptEntity = created
        }

        let existingBoundary = MessengerReceiptBoundaryMath.boundary(from: receiptEntity, kind: kind)
        guard MessengerReceiptBoundaryMath.shouldAdvance(
            incoming: incomingBoundary,
            over: existingBoundary
        ) else {
            return .noop
        }

        switch kind {
        case .delivered:
            receiptEntity.lastDeliveredAt = incomingBoundary.createdAt
            receiptEntity.lastDeliveredMessageID = incomingBoundary.messageID.uuidString
        case .read:
            receiptEntity.lastReadAt = incomingBoundary.createdAt
            receiptEntity.lastReadMessageID = incomingBoundary.messageID.uuidString
            if let deliveredBoundary = MessengerReceiptBoundaryMath.boundary(
                from: receiptEntity,
                kind: .delivered
            ) {
                if incomingBoundary > deliveredBoundary {
                    receiptEntity.lastDeliveredAt = incomingBoundary.createdAt
                    receiptEntity.lastDeliveredMessageID = incomingBoundary.messageID.uuidString
                }
            } else {
                receiptEntity.lastDeliveredAt = incomingBoundary.createdAt
                receiptEntity.lastDeliveredMessageID = incomingBoundary.messageID.uuidString
            }
        }
        receiptEntity.localUpdatedAt = syncedAt

        var updatedMessageCount = 0
        var previewDeliveryStatus: MessageDeliveryStatus?
        var updatedConversationPreview = false

        let isCounterpartyReceipt = participantProfileID != ownerProfileID
        if isCounterpartyReceipt {
            let messages = try fetchOutgoingMessages(
                conversationID: conversationKey,
                ownerProfileID: ownerProfileID,
                context: context
            )

            for message in messages {
                guard MessengerReceiptBoundaryMath.messageQualifiesForReceipt(
                    senderProfileID: message.senderProfileID,
                    ownerProfileID: ownerProfileID,
                    deletedAt: message.deletedAt,
                    localState: message.localState,
                    messageCreatedAt: message.createdAt,
                    boundary: incomingBoundary
                ) else {
                    continue
                }

                let current = message.deliveryStatus.flatMap(MessageDeliveryStatus.init(rawValue:))
                guard let upgraded = MessengerReceiptBoundaryMath.upgradedStatus(
                    current: current,
                    applying: kind
                ) else {
                    continue
                }

                message.deliveryStatus = upgraded.rawValue
                message.localUpdatedAt = syncedAt
                updatedMessageCount += 1
            }

            if let conversationEntity = try fetchConversationEntity(id: conversationKey, context: context),
               conversationEntity.lastMessageSenderProfileID == ownerProfileID.uuidString,
               let lastCreatedAt = conversationEntity.lastMessageCreatedAt,
               lastCreatedAt <= incomingBoundary.createdAt {
                let currentPreview = conversationEntity.lastMessageDeliveryStatus
                    .flatMap(MessageDeliveryStatus.init(rawValue:))
                if let upgraded = MessengerReceiptBoundaryMath.upgradedStatus(
                    current: currentPreview,
                    applying: kind
                ) {
                    conversationEntity.lastMessageDeliveryStatus = upgraded.rawValue
                    conversationEntity.localUpdatedAt = syncedAt
                    previewDeliveryStatus = upgraded
                    updatedConversationPreview = true
                }
            }
        }

        try context.save()

        return MessengerReceiptApplyResult(
            didAdvanceParticipantBoundary: true,
            updatedMessageCount: updatedMessageCount,
            updatedConversationPreview: updatedConversationPreview,
            targetMessageFound: true,
            requiresSyncRepair: false,
            previewDeliveryStatus: previewDeliveryStatus
        )
    }

    private func fetchOutgoingMessages(
        conversationID: String,
        ownerProfileID: UUID,
        context: ModelContext
    ) throws -> [LocalMessengerMessage] {
        let ownerKey = ownerProfileID.uuidString
        let descriptor = FetchDescriptor<LocalMessengerMessage>(
            predicate: #Predicate { message in
                message.conversationID == conversationID
                    && message.senderProfileID == ownerKey
            }
        )
        return try context.fetch(descriptor)
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
                existing.lastAttemptedSyncAt = mapped.lastAttemptedSyncAt ?? existing.lastAttemptedSyncAt
                existing.lastFailedAt = mapped.lastFailedAt ?? existing.lastFailedAt
                existing.lastErrorCode = mapped.lastErrorCode ?? existing.lastErrorCode
                existing.state = mapped.state ?? existing.state
                existing.needsFullRefresh = mapped.needsFullRefresh
                existing.lastBootstrapAt = mapped.lastBootstrapAt ?? existing.lastBootstrapAt
                existing.lastKnownServerRevision = mapped.lastKnownServerRevision ?? existing.lastKnownServerRevision
                existing.localUpdatedAt = syncedAt
            } else {
                existing.lastAppliedRevision = mapped.lastAppliedRevision ?? existing.lastAppliedRevision
                existing.lastSuccessfulSyncAt = mapped.lastSuccessfulSyncAt ?? existing.lastSuccessfulSyncAt
                existing.lastFullRefreshAt = mapped.lastFullRefreshAt ?? existing.lastFullRefreshAt
                existing.lastAttemptedSyncAt = mapped.lastAttemptedSyncAt ?? existing.lastAttemptedSyncAt
                existing.lastFailedAt = mapped.lastFailedAt ?? existing.lastFailedAt
                existing.lastErrorCode = mapped.lastErrorCode ?? existing.lastErrorCode
                existing.state = mapped.state ?? existing.state
                existing.needsFullRefresh = mapped.needsFullRefresh
                existing.lastBootstrapAt = mapped.lastBootstrapAt ?? existing.lastBootstrapAt
                existing.lastKnownServerRevision = mapped.lastKnownServerRevision ?? existing.lastKnownServerRevision
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

    func commitAuthoritativeSyncPage(
        ownerProfileID: UUID,
        advancedRevision: Int64?,
        safeBoundaries: [UUID: MessageReceiptBoundary]
    ) async throws -> [UUID: MessageReceiptBoundary] {
        let context = modelContext
        let now = Date()

        if let advancedRevision {
            try advanceSyncCursor(
                to: advancedRevision,
                syncedAt: now,
                context: context
            )
        }

        var committed: [UUID: MessageReceiptBoundary] = [:]
        for (conversationID, boundary) in safeBoundaries {
            let merged = try mergePendingDeliveryBoundary(
                ownerProfileID: ownerProfileID,
                conversationID: conversationID,
                boundary: boundary,
                updatedAt: now,
                context: context
            )
            committed[conversationID] = merged
        }

        try context.save()
        return committed
    }

    func loadPendingDeliveryBoundaries(
        ownerProfileID: UUID
    ) async throws -> [UUID: MessageReceiptBoundary] {
        let context = modelContext
        let descriptor = FetchDescriptor<LocalMessengerPendingDeliveryReceipt>(
            predicate: #Predicate { $0.ownerProfileID == ownerProfileID }
        )
        var result: [UUID: MessageReceiptBoundary] = [:]
        for entity in try context.fetch(descriptor) {
            result[entity.conversationID] = MessageReceiptBoundary(
                createdAt: entity.createdAt,
                messageID: entity.messageID
            )
        }
        return result
    }

    func clearPendingDeliveryBoundary(
        ownerProfileID: UUID,
        conversationID: UUID,
        through boundary: MessageReceiptBoundary
    ) async throws {
        let context = modelContext
        let key = LocalMessengerPendingDeliveryReceipt.makeKey(
            ownerProfileID: ownerProfileID,
            conversationID: conversationID
        )
        guard let entity = try fetchPendingDeliveryReceiptEntity(key: key, context: context) else {
            return
        }

        let persisted = MessageReceiptBoundary(
            createdAt: entity.createdAt,
            messageID: entity.messageID
        )

        if persisted > boundary {
            MessengerDiagnostics.event(
                .messengerDeliveryAckPendingRetainedHigherBoundary,
                conversationID: conversationID,
                messageID: entity.messageID,
                metadata: ["reason": "persistedHigherThanAck"]
            )
            return
        }

        context.delete(entity)
        try context.save()
    }

    func clearPendingDeliveryBoundaries(
        ownerProfileID: UUID
    ) async throws {
        let context = modelContext
        let descriptor = FetchDescriptor<LocalMessengerPendingDeliveryReceipt>(
            predicate: #Predicate { $0.ownerProfileID == ownerProfileID }
        )
        let entities = try context.fetch(descriptor)
        guard !entities.isEmpty else { return }
        for entity in entities {
            context.delete(entity)
        }
        try context.save()
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

    func clearAllConfirmedMediaCacheMetadata() async throws {
        let context = modelContext
        let attachments = try context.fetch(FetchDescriptor<LocalMessengerAttachment>())
        let now = Date()
        for attachment in attachments {
            attachment.hasLocalThumbnail = false
            attachment.hasLocalFullImage = false
            attachment.localThumbnailByteSize = nil
            attachment.localFullByteSize = nil
            attachment.mediaCachedAt = nil
            attachment.mediaLastAccessedAt = nil
            attachment.localUpdatedAt = now
        }
        if !attachments.isEmpty {
            try context.save()
        }
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
            kind: .text,
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
        if let pendingMediaID = entity.pendingMediaID,
           let media = try fetchPendingMediaEntity(pendingMediaID: pendingMediaID, context: context) {
            MessengerPendingMediaStore.delete(relativePath: media.localRelativePath)
            context.delete(media)
        } else if let media = try fetchPendingMediaEntity(clientMessageID: clientMessageID, context: context) {
            MessengerPendingMediaStore.delete(relativePath: media.localRelativePath)
            context.delete(media)
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
        try await clearPendingMedia()
        let context = modelContext
        try context.delete(model: LocalMessengerOutboxItem.self)
        try context.save()
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
        let context = modelContext
        let now = Date()

        if let existing = try fetchOutboxEntity(clientMessageID: clientMessageID, context: context) {
            return MessengerLocalMapping.outboxSnapshot(from: existing)
        }

        let media = MessengerLocalMapping.mapPendingMedia(
            pendingMediaID: pendingMediaID,
            clientMessageID: clientMessageID,
            conversationID: conversationID,
            localRelativePath: localRelativePath,
            contentType: contentType,
            byteSize: byteSize,
            width: width,
            height: height,
            createdAt: now,
            updatedAt: now
        )
        context.insert(media)

        let outbox = MessengerLocalMapping.mapOutboxItem(
            conversationID: conversationID,
            clientMessageID: clientMessageID,
            kind: .image,
            body: caption ?? "",
            replyToMessageID: replyToMessageID,
            status: .pending,
            attemptCount: 0,
            lastErrorCode: nil,
            nextRetryAt: now,
            createdAt: now,
            updatedAt: now,
            lastAttemptAt: nil,
            serverMessageID: nil,
            pendingMediaID: pendingMediaID
        )
        context.insert(outbox)
        try context.save()
        return MessengerLocalMapping.outboxSnapshot(from: outbox)
    }

    func fetchPendingMedia(clientMessageID: String) async throws -> MessengerPendingMediaSnapshot? {
        let context = modelContext
        guard let entity = try fetchPendingMediaEntity(clientMessageID: clientMessageID, context: context) else {
            return nil
        }
        return MessengerLocalMapping.pendingMediaSnapshot(from: entity)
    }

    func fetchPendingMedia(pendingMediaID: String) async throws -> MessengerPendingMediaSnapshot? {
        let context = modelContext
        guard let entity = try fetchPendingMediaEntity(pendingMediaID: pendingMediaID, context: context) else {
            return nil
        }
        return MessengerLocalMapping.pendingMediaSnapshot(from: entity)
    }

    func deletePendingMedia(clientMessageID: String) async throws {
        let context = modelContext
        guard let entity = try fetchPendingMediaEntity(clientMessageID: clientMessageID, context: context) else {
            return
        }
        MessengerPendingMediaStore.delete(relativePath: entity.localRelativePath)
        context.delete(entity)
        try context.save()
    }

    func clearPendingMedia() async throws {
        let context = modelContext
        try context.delete(model: LocalMessengerPendingMedia.self)
        try context.save()
        MessengerPendingMediaStore.clearAll()
    }

    func fetchPendingMediaRelativePaths() async throws -> Set<String> {
        let context = modelContext
        let descriptor = FetchDescriptor<LocalMessengerPendingMedia>()
        return Set(try context.fetch(descriptor).map(\.localRelativePath))
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

    /// Monotonically advances the persisted sync cursor without saving; the caller
    /// owns the single `context.save()` so the cursor commit is atomic with the
    /// proven-safe delivery boundary merge.
    func advanceSyncCursor(
        to revision: Int64,
        syncedAt: Date,
        context: ModelContext
    ) throws {
        let globalID = MessengerPersistence.syncMetadataGlobalID
        if let existing = try fetchSyncMetadataEntity(id: globalID, context: context) {
            let current = existing.lastAppliedRevision ?? revision
            existing.lastAppliedRevision = Swift.max(current, revision)
            existing.localUpdatedAt = syncedAt
        } else {
            let entity = LocalMessengerSyncMetadata(
                id: globalID,
                lastAppliedRevision: revision,
                lastSuccessfulSyncAt: nil,
                lastFullRefreshAt: nil,
                schemaVersion: MessengerPersistence.schemaVersion,
                localUpdatedAt: syncedAt
            )
            context.insert(entity)
        }
    }

    /// Monotonically merges a proven-safe delivery boundary without saving.
    /// Returns the resulting highest persisted boundary for the conversation.
    func mergePendingDeliveryBoundary(
        ownerProfileID: UUID,
        conversationID: UUID,
        boundary: MessageReceiptBoundary,
        updatedAt: Date,
        context: ModelContext
    ) throws -> MessageReceiptBoundary {
        let key = LocalMessengerPendingDeliveryReceipt.makeKey(
            ownerProfileID: ownerProfileID,
            conversationID: conversationID
        )

        if let existing = try fetchPendingDeliveryReceiptEntity(key: key, context: context) {
            let persisted = MessageReceiptBoundary(
                createdAt: existing.createdAt,
                messageID: existing.messageID
            )
            guard boundary > persisted else {
                return persisted
            }
            existing.createdAt = boundary.createdAt
            existing.messageID = boundary.messageID
            existing.updatedAt = updatedAt
            return boundary
        }

        let entity = LocalMessengerPendingDeliveryReceipt(
            key: key,
            ownerProfileID: ownerProfileID,
            conversationID: conversationID,
            createdAt: boundary.createdAt,
            messageID: boundary.messageID,
            updatedAt: updatedAt
        )
        context.insert(entity)
        return boundary
    }

    func fetchPendingDeliveryReceiptEntity(
        key: String,
        context: ModelContext
    ) throws -> LocalMessengerPendingDeliveryReceipt? {
        var descriptor = FetchDescriptor<LocalMessengerPendingDeliveryReceipt>(
            predicate: #Predicate { $0.key == key }
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

    func fetchAttachmentSnapshots(
        messageIDs: Set<String>,
        conversationID: String,
        context: ModelContext
    ) throws -> [String: [LocalAttachmentSnapshot]] {
        guard !messageIDs.isEmpty else { return [:] }

        let descriptor = FetchDescriptor<LocalMessengerAttachment>(
            predicate: #Predicate { attachment in
                attachment.conversationID == conversationID
            }
        )
        let snapshots = try context.fetch(descriptor)
            .filter { messageIDs.contains($0.messageID) }
            .map(MessengerLocalMapping.attachmentSnapshot(from:))
        return Dictionary(grouping: snapshots, by: \.messageID)
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

    func fetchReactionAggregateSnapshots(
        messageIDs: Set<String>,
        conversationID: String,
        context: ModelContext
    ) throws -> [String: [LocalReactionAggregateSnapshot]] {
        guard !messageIDs.isEmpty else { return [:] }

        let descriptor = FetchDescriptor<LocalMessengerReactionAggregate>(
            predicate: #Predicate { aggregate in
                aggregate.conversationID == conversationID
            }
        )
        let snapshots = try context.fetch(descriptor)
            .filter { messageIDs.contains($0.messageID) }
            .map(MessengerLocalMapping.reactionAggregateSnapshot(from:))
        return Dictionary(grouping: snapshots, by: \.messageID)
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

    func fetchPendingMediaEntity(
        clientMessageID: String,
        context: ModelContext
    ) throws -> LocalMessengerPendingMedia? {
        var descriptor = FetchDescriptor<LocalMessengerPendingMedia>(
            predicate: #Predicate { $0.clientMessageID == clientMessageID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchPendingMediaEntity(
        pendingMediaID: String,
        context: ModelContext
    ) throws -> LocalMessengerPendingMedia? {
        var descriptor = FetchDescriptor<LocalMessengerPendingMedia>(
            predicate: #Predicate { $0.pendingMediaID == pendingMediaID }
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
