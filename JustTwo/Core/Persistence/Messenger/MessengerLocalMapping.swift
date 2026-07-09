import Foundation

enum MessengerLocalMapping {
    static func mapConversation(
        from dto: ConversationDTO,
        syncedAt: Date = Date()
    ) -> LocalMessengerConversation {
        let participant = dto.otherParticipant
        let photo = participant?.profile.primaryPhoto
        let lastMessage = dto.lastMessage
        let preview = lastMessagePreviewFields(from: lastMessage)

        return LocalMessengerConversation(
            id: dto.id.uuidString,
            type: dto.type,
            status: dto.status,
            connectionID: dto.connectionID?.uuidString,
            createdAt: dto.createdAt ?? dto.updatedAt ?? syncedAt,
            updatedAt: dto.updatedAt,
            lastMessageAt: dto.lastMessageAt,
            lastReadAt: dto.lastReadAt,
            unreadCount: dto.unreadCount,
            otherParticipantProfileID: participant?.profile.id.uuidString,
            otherParticipantDisplayName: participant?.profile.displayName,
            otherParticipantPrimaryPhotoID: photo?.id.uuidString,
            otherParticipantPrimaryPhotoDownloadURLExpiresAt: nil,
            lastMessageID: lastMessage?.id.uuidString,
            lastMessageKind: preview.kind,
            lastMessageBody: preview.body,
            lastMessageSenderProfileID: lastMessage?.senderProfileID.uuidString,
            lastMessageCreatedAt: lastMessage?.createdAt,
            lastMessageDeletedAt: lastMessage?.deletedAt,
            lastSyncedAt: syncedAt,
            localUpdatedAt: syncedAt
        )
    }

    private static func lastMessagePreviewFields(from message: MessageDTO?) -> (kind: String?, body: String?) {
        guard let message else { return (nil, nil) }
        if message.deletedAt != nil {
            return (message.kind.rawValue, nil)
        }
        if message.kind == .image {
            return (message.kind.rawValue, String(localized: "chats.message.photo", defaultValue: "Photo"))
        }
        return (message.kind.rawValue, message.body)
    }

    static func mapMessage(
        from dto: MessageDTO,
        syncedAt: Date = Date()
    ) -> LocalMessengerMessage {
        let isDeleted = dto.deletedAt != nil
        let localState: LocalMessengerMessageState = isDeleted ? .deleted : .serverConfirmed

        return LocalMessengerMessage(
            id: dto.id.uuidString,
            conversationID: dto.conversationID.uuidString,
            clientMessageID: dto.clientMessageID,
            senderProfileID: dto.senderProfileID.uuidString,
            kind: dto.kind.rawValue,
            body: isDeleted ? nil : dto.body,
            createdAt: dto.createdAt ?? syncedAt,
            editedAt: dto.editedAt,
            deletedAt: dto.deletedAt,
            deliveryStatus: dto.deliveryStatus?.rawValue,
            replyToMessageID: dto.replyTo?.id.uuidString,
            replyToBody: dto.replyTo?.body,
            replyToSenderProfileID: dto.replyTo?.senderProfileID.uuidString,
            localState: localState.rawValue,
            localCreatedAt: syncedAt,
            localUpdatedAt: syncedAt
        )
    }

    static func mapAttachments(
        from dto: MessageDTO,
        syncedAt: Date = Date()
    ) -> [LocalMessengerAttachment] {
        guard dto.deletedAt == nil else { return [] }

        return dto.attachments.map { attachment in
            let cacheKey = attachment.id.uuidString.lowercased()
            return LocalMessengerAttachment(
                id: cacheKey,
                messageID: dto.id.uuidString,
                conversationID: dto.conversationID.uuidString,
                kind: MessageKind.image.rawValue,
                contentType: attachment.contentType,
                byteSize: attachment.byteSize,
                width: attachment.width,
                height: attachment.height,
                createdAt: dto.createdAt,
                localCacheKey: cacheKey,
                downloadURLExpiresAt: attachment.downloadUrlExpiresAt,
                localUpdatedAt: syncedAt
            )
        }
    }

    static func mapReactionAggregates(
        from dto: MessageDTO,
        syncedAt: Date = Date()
    ) -> [LocalMessengerReactionAggregate] {
        guard dto.deletedAt == nil else { return [] }

        let conversationID = dto.conversationID.uuidString
        let messageID = dto.id.uuidString

        return dto.reactions
            .filter { $0.count > 0 }
            .map { reaction in
                LocalMessengerReactionAggregate(
                    id: reactionAggregateIdentity(messageID: messageID, emoji: reaction.emoji),
                    messageID: messageID,
                    conversationID: conversationID,
                    emoji: reaction.emoji,
                    count: reaction.count,
                    reactedByMe: reaction.reactedByMe,
                    localUpdatedAt: syncedAt
                )
            }
    }

    static func mapReceipt(
        from dto: MessengerReceiptDTO,
        syncedAt: Date = Date()
    ) -> LocalMessengerReceipt {
        LocalMessengerReceipt(
            id: receiptIdentity(
                conversationID: dto.conversationID.uuidString,
                profileID: dto.profileID.uuidString
            ),
            conversationID: dto.conversationID.uuidString,
            profileID: dto.profileID.uuidString,
            lastDeliveredAt: dto.deliveredAt,
            lastReadAt: dto.readAt,
            lastDeliveredMessageID: dto.deliveredAt == nil ? nil : dto.messageID?.uuidString,
            lastReadMessageID: dto.readAt == nil ? nil : dto.messageID?.uuidString,
            localUpdatedAt: syncedAt
        )
    }

    static func mapSyncMetadata(
        from snapshot: LocalMessengerSyncMetadataSnapshot,
        syncedAt: Date = Date()
    ) -> LocalMessengerSyncMetadata {
        LocalMessengerSyncMetadata(
            id: snapshot.id,
            lastAppliedRevision: snapshot.lastAppliedRevision,
            lastSuccessfulSyncAt: snapshot.lastSuccessfulSyncAt,
            lastFullRefreshAt: snapshot.lastFullRefreshAt,
            schemaVersion: snapshot.schemaVersion,
            localUpdatedAt: syncedAt
        )
    }

    static func conversationSnapshot(from entity: LocalMessengerConversation) -> LocalConversationSnapshot {
        LocalConversationSnapshot(
            id: entity.id,
            type: entity.type,
            status: entity.status,
            connectionID: entity.connectionID,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            lastMessageAt: entity.lastMessageAt,
            lastReadAt: entity.lastReadAt,
            unreadCount: entity.unreadCount,
            otherParticipantProfileID: entity.otherParticipantProfileID,
            otherParticipantDisplayName: entity.otherParticipantDisplayName,
            otherParticipantPrimaryPhotoID: entity.otherParticipantPrimaryPhotoID,
            otherParticipantPrimaryPhotoDownloadURLExpiresAt: entity.otherParticipantPrimaryPhotoDownloadURLExpiresAt,
            lastMessageID: entity.lastMessageID,
            lastMessageKind: entity.lastMessageKind,
            lastMessageBody: entity.lastMessageBody,
            lastMessageSenderProfileID: entity.lastMessageSenderProfileID,
            lastMessageCreatedAt: entity.lastMessageCreatedAt,
            lastMessageDeletedAt: entity.lastMessageDeletedAt,
            lastSyncedAt: entity.lastSyncedAt,
            localUpdatedAt: entity.localUpdatedAt
        )
    }

    static func messageSnapshot(
        from entity: LocalMessengerMessage,
        attachments: [LocalAttachmentSnapshot],
        reactions: [LocalReactionAggregateSnapshot]
    ) -> LocalMessageSnapshot {
        LocalMessageSnapshot(
            id: entity.id,
            conversationID: entity.conversationID,
            clientMessageID: entity.clientMessageID,
            senderProfileID: entity.senderProfileID,
            kind: entity.kind,
            body: entity.body,
            createdAt: entity.createdAt,
            editedAt: entity.editedAt,
            deletedAt: entity.deletedAt,
            deliveryStatus: entity.deliveryStatus,
            replyToMessageID: entity.replyToMessageID,
            replyToBody: entity.replyToBody,
            replyToSenderProfileID: entity.replyToSenderProfileID,
            localState: LocalMessengerMessageState(rawValue: entity.localState) ?? .serverConfirmed,
            localCreatedAt: entity.localCreatedAt,
            localUpdatedAt: entity.localUpdatedAt,
            attachments: attachments,
            reactions: reactions
        )
    }

    static func attachmentSnapshot(from entity: LocalMessengerAttachment) -> LocalAttachmentSnapshot {
        LocalAttachmentSnapshot(
            id: entity.id,
            messageID: entity.messageID,
            conversationID: entity.conversationID,
            kind: entity.kind,
            contentType: entity.contentType,
            byteSize: entity.byteSize,
            width: entity.width,
            height: entity.height,
            createdAt: entity.createdAt,
            localCacheKey: entity.localCacheKey,
            downloadURLExpiresAt: entity.downloadURLExpiresAt,
            hasLocalThumbnail: entity.hasLocalThumbnail ?? false,
            hasLocalFullImage: entity.hasLocalFullImage ?? false,
            localThumbnailByteSize: entity.localThumbnailByteSize,
            localFullByteSize: entity.localFullByteSize,
            mediaCachedAt: entity.mediaCachedAt,
            mediaLastAccessedAt: entity.mediaLastAccessedAt,
            localUpdatedAt: entity.localUpdatedAt
        )
    }

    static func reactionAggregateSnapshot(from entity: LocalMessengerReactionAggregate) -> LocalReactionAggregateSnapshot {
        LocalReactionAggregateSnapshot(
            id: entity.id,
            messageID: entity.messageID,
            conversationID: entity.conversationID,
            emoji: entity.emoji,
            count: entity.count,
            reactedByMe: entity.reactedByMe,
            localUpdatedAt: entity.localUpdatedAt
        )
    }

    static func receiptSnapshot(from entity: LocalMessengerReceipt) -> LocalReceiptSnapshot {
        LocalReceiptSnapshot(
            id: entity.id,
            conversationID: entity.conversationID,
            profileID: entity.profileID,
            lastDeliveredAt: entity.lastDeliveredAt,
            lastReadAt: entity.lastReadAt,
            lastDeliveredMessageID: entity.lastDeliveredMessageID,
            lastReadMessageID: entity.lastReadMessageID,
            localUpdatedAt: entity.localUpdatedAt
        )
    }

    static func syncMetadataSnapshot(from entity: LocalMessengerSyncMetadata) -> LocalMessengerSyncMetadataSnapshot {
        LocalMessengerSyncMetadataSnapshot(
            id: entity.id,
            lastAppliedRevision: entity.lastAppliedRevision,
            lastSuccessfulSyncAt: entity.lastSuccessfulSyncAt,
            lastFullRefreshAt: entity.lastFullRefreshAt,
            schemaVersion: entity.schemaVersion,
            localUpdatedAt: entity.localUpdatedAt
        )
    }

    static func applyLastMessage(
        from message: MessageDTO,
        to target: LocalMessengerConversation,
        syncedAt: Date
    ) {
        let preview = lastMessagePreviewFields(from: message)
        target.lastMessageID = message.id.uuidString
        target.lastMessageKind = preview.kind
        target.lastMessageBody = preview.body
        target.lastMessageSenderProfileID = message.senderProfileID.uuidString
        target.lastMessageCreatedAt = message.createdAt
        target.lastMessageDeletedAt = message.deletedAt
        target.lastSyncedAt = syncedAt
        target.localUpdatedAt = syncedAt
    }

    static func applyConversation(_ source: LocalMessengerConversation, to target: LocalMessengerConversation) {
        target.type = source.type
        target.status = source.status
        target.connectionID = source.connectionID
        target.createdAt = source.createdAt
        target.updatedAt = source.updatedAt
        target.lastMessageAt = source.lastMessageAt
        target.lastReadAt = source.lastReadAt
        target.unreadCount = source.unreadCount
        target.otherParticipantProfileID = source.otherParticipantProfileID
        target.otherParticipantDisplayName = source.otherParticipantDisplayName
        target.otherParticipantPrimaryPhotoID = source.otherParticipantPrimaryPhotoID
        target.otherParticipantPrimaryPhotoDownloadURLExpiresAt = source.otherParticipantPrimaryPhotoDownloadURLExpiresAt
        target.lastMessageID = source.lastMessageID
        target.lastMessageKind = source.lastMessageKind
        target.lastMessageBody = source.lastMessageBody
        target.lastMessageSenderProfileID = source.lastMessageSenderProfileID
        target.lastMessageCreatedAt = source.lastMessageCreatedAt
        target.lastMessageDeletedAt = source.lastMessageDeletedAt
        target.lastSyncedAt = source.lastSyncedAt
        target.localUpdatedAt = source.localUpdatedAt
    }

    static func applyMessage(_ source: LocalMessengerMessage, to target: LocalMessengerMessage) {
        target.conversationID = source.conversationID
        target.clientMessageID = source.clientMessageID
        target.senderProfileID = source.senderProfileID
        target.kind = source.kind
        target.body = source.body
        target.createdAt = source.createdAt
        target.editedAt = source.editedAt
        target.deletedAt = source.deletedAt
        target.deliveryStatus = source.deliveryStatus
        target.replyToMessageID = source.replyToMessageID
        target.replyToBody = source.replyToBody
        target.replyToSenderProfileID = source.replyToSenderProfileID
        target.localState = source.localState
        target.localUpdatedAt = source.localUpdatedAt
    }

    static func applyAttachment(_ source: LocalMessengerAttachment, to target: LocalMessengerAttachment) {
        target.messageID = source.messageID
        target.conversationID = source.conversationID
        target.kind = source.kind
        target.contentType = source.contentType
        target.byteSize = source.byteSize
        target.width = source.width
        target.height = source.height
        target.createdAt = source.createdAt
        target.localCacheKey = source.localCacheKey
        target.downloadURLExpiresAt = source.downloadURLExpiresAt
        target.hasLocalThumbnail = source.hasLocalThumbnail
        target.hasLocalFullImage = source.hasLocalFullImage
        target.localThumbnailByteSize = source.localThumbnailByteSize
        target.localFullByteSize = source.localFullByteSize
        target.mediaCachedAt = source.mediaCachedAt
        target.mediaLastAccessedAt = source.mediaLastAccessedAt
        target.localUpdatedAt = source.localUpdatedAt
    }

    static func applyAttachmentMediaMetadata(
        from source: LocalMessengerAttachment,
        to target: LocalMessengerAttachment
    ) {
        target.hasLocalThumbnail = source.hasLocalThumbnail
        target.hasLocalFullImage = source.hasLocalFullImage
        target.localThumbnailByteSize = source.localThumbnailByteSize
        target.localFullByteSize = source.localFullByteSize
        target.mediaCachedAt = source.mediaCachedAt
        target.mediaLastAccessedAt = source.mediaLastAccessedAt
    }

    static func applyReceipt(_ incoming: LocalMessengerReceipt, to existing: LocalMessengerReceipt) {
        if let deliveredAt = incoming.lastDeliveredAt {
            if let current = existing.lastDeliveredAt {
                if deliveredAt > current {
                    existing.lastDeliveredAt = deliveredAt
                    existing.lastDeliveredMessageID = incoming.lastDeliveredMessageID
                }
            } else {
                existing.lastDeliveredAt = deliveredAt
                existing.lastDeliveredMessageID = incoming.lastDeliveredMessageID
            }
        }

        if let readAt = incoming.lastReadAt {
            if let current = existing.lastReadAt {
                if readAt > current {
                    existing.lastReadAt = readAt
                    existing.lastReadMessageID = incoming.lastReadMessageID
                }
            } else {
                existing.lastReadAt = readAt
                existing.lastReadMessageID = incoming.lastReadMessageID
            }

            if let deliveredAt = existing.lastDeliveredAt {
                if readAt > deliveredAt {
                    existing.lastDeliveredAt = readAt
                    if existing.lastDeliveredMessageID == nil {
                        existing.lastDeliveredMessageID = incoming.lastReadMessageID
                    }
                }
            } else {
                existing.lastDeliveredAt = readAt
                existing.lastDeliveredMessageID = incoming.lastReadMessageID
            }
        }

        existing.localUpdatedAt = max(existing.localUpdatedAt, incoming.localUpdatedAt)
    }

    static func applyReactionAggregate(
        _ source: LocalMessengerReactionAggregate,
        to target: LocalMessengerReactionAggregate
    ) {
        target.count = source.count
        target.reactedByMe = source.reactedByMe
        target.localUpdatedAt = source.localUpdatedAt
    }

    static func reactionAggregateIdentity(messageID: String, emoji: String) -> String {
        "\(messageID):\(emoji)"
    }

    static func receiptIdentity(conversationID: String, profileID: String) -> String {
        "\(conversationID):\(profileID)"
    }

    static func mapOutboxItem(
        conversationID: UUID,
        clientMessageID: String,
        kind: MessengerOutboxItemKind,
        body: String,
        replyToMessageID: UUID?,
        status: MessengerOutboxItemStatus,
        attemptCount: Int,
        lastErrorCode: String?,
        nextRetryAt: Date?,
        createdAt: Date,
        updatedAt: Date,
        lastAttemptAt: Date?,
        serverMessageID: UUID?,
        pendingMediaID: String? = nil
    ) -> LocalMessengerOutboxItem {
        LocalMessengerOutboxItem(
            id: UUID().uuidString,
            conversationID: conversationID.uuidString,
            clientMessageID: clientMessageID,
            kind: kind.rawValue,
            body: body,
            replyToMessageID: replyToMessageID?.uuidString,
            status: status.rawValue,
            attemptCount: attemptCount,
            lastErrorCode: lastErrorCode,
            nextRetryAt: nextRetryAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastAttemptAt: lastAttemptAt,
            serverMessageID: serverMessageID?.uuidString,
            pendingMediaID: pendingMediaID
        )
    }

    static func outboxSnapshot(from entity: LocalMessengerOutboxItem) -> MessengerOutboxItemSnapshot {
        MessengerOutboxItemSnapshot(
            id: entity.id,
            conversationID: entity.conversationID,
            clientMessageID: entity.clientMessageID,
            kind: MessengerOutboxItemKind(rawValue: entity.kind) ?? .text,
            body: entity.body,
            replyToMessageID: entity.replyToMessageID,
            status: MessengerOutboxItemStatus(rawValue: entity.status) ?? .pending,
            attemptCount: entity.attemptCount,
            lastErrorCode: entity.lastErrorCode,
            nextRetryAt: entity.nextRetryAt,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            lastAttemptAt: entity.lastAttemptAt,
            serverMessageID: entity.serverMessageID,
            pendingMediaID: entity.pendingMediaID
        )
    }

    static func applyOutboxSnapshot(_ snapshot: MessengerOutboxItemSnapshot, to entity: LocalMessengerOutboxItem) {
        entity.conversationID = snapshot.conversationID
        entity.clientMessageID = snapshot.clientMessageID
        entity.kind = snapshot.kind.rawValue
        entity.body = snapshot.body
        entity.replyToMessageID = snapshot.replyToMessageID
        entity.status = snapshot.status.rawValue
        entity.attemptCount = snapshot.attemptCount
        entity.lastErrorCode = snapshot.lastErrorCode
        entity.nextRetryAt = snapshot.nextRetryAt
        entity.createdAt = snapshot.createdAt
        entity.updatedAt = snapshot.updatedAt
        entity.lastAttemptAt = snapshot.lastAttemptAt
        entity.serverMessageID = snapshot.serverMessageID
        entity.pendingMediaID = snapshot.pendingMediaID
    }

    static func mapPendingMedia(
        pendingMediaID: String,
        clientMessageID: String,
        conversationID: UUID,
        localRelativePath: String,
        contentType: String,
        byteSize: Int,
        width: Int,
        height: Int,
        createdAt: Date,
        updatedAt: Date
    ) -> LocalMessengerPendingMedia {
        LocalMessengerPendingMedia(
            id: UUID().uuidString,
            pendingMediaID: pendingMediaID,
            clientMessageID: clientMessageID,
            conversationID: conversationID.uuidString,
            localRelativePath: localRelativePath,
            contentType: contentType,
            byteSize: byteSize,
            width: width,
            height: height,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func pendingMediaSnapshot(from entity: LocalMessengerPendingMedia) -> MessengerPendingMediaSnapshot {
        MessengerPendingMediaSnapshot(
            id: entity.id,
            pendingMediaID: entity.pendingMediaID,
            clientMessageID: entity.clientMessageID,
            conversationID: entity.conversationID,
            localRelativePath: entity.localRelativePath,
            contentType: entity.contentType,
            byteSize: entity.byteSize,
            width: entity.width,
            height: entity.height,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }
}

#if DEBUG
extension MessengerLocalMapping {
    static func persistedFieldNames(for entity: Any) -> [String: String] {
        switch entity {
        case let conversation as LocalMessengerConversation:
            return [
                "id": conversation.id,
                "otherParticipantPrimaryPhotoID": conversation.otherParticipantPrimaryPhotoID ?? ""
            ]
        case let message as LocalMessengerMessage:
            return [
                "id": message.id,
                "body": message.body ?? "",
                "localState": message.localState
            ]
        case let attachment as LocalMessengerAttachment:
            return [
                "id": attachment.id,
                "localCacheKey": attachment.localCacheKey ?? ""
            ]
        default:
            return [:]
        }
    }
}
#endif
