import Foundation

enum MessengerConversationCacheSource: String, Sendable {
    case cache
    case rest
    case delta
    case realtime
}

@MainActor
enum MessengerConversationCacheService {

    #if DEBUG
    static var testingStore: MessengerLocalStore?
    #endif

    private static var localStore: MessengerLocalStore {
        #if DEBUG
        if let testingStore {
            return testingStore
        }
        #endif
        return .shared
    }

    static func hydrateCachedPreviews(currentProfileID: UUID) async -> [ChatConversationPreview]? {
        guard MessengerLocalStorageFeatureFlags.isCachedConversationListEnabled else { return nil }

        let startedAt = Date()
        MessengerDiagnostics.event(.messengerConversationCacheLoadStarted)

        do {
            let snapshots = try await localStore.fetchLocalConversations()
            guard !snapshots.isEmpty else {
                MessengerDiagnostics.event(
                    .messengerConversationCacheEmpty,
                    metadata: ["durationMs": "\(durationMilliseconds(since: startedAt))"]
                )
                return nil
            }

            let previews = snapshots.compactMap {
                ChatUIMapping.conversationPreview(from: $0, currentProfileID: currentProfileID)
            }

            PresenceStore.shared.hydrateFromCacheSnapshots(snapshots)

            MessengerDiagnostics.event(
                .messengerConversationCacheLoadSucceeded,
                metadata: [
                    "count": "\(previews.count)",
                    "durationMs": "\(durationMilliseconds(since: startedAt))"
                ]
            )
            return previews
        } catch {
            MessengerDiagnostics.event(
                .messengerConversationCacheLoadFailed,
                metadata: [
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "durationMs": "\(durationMilliseconds(since: startedAt))"
                ]
            )
            return nil
        }
    }

    @discardableResult
    static func persistRESTConversations(_ conversations: [ConversationDTO]) async -> Bool {
        await upsertConversations(conversations, source: .rest)
    }

    static func persistDeltaConversation(
        _ conversation: ConversationDTO?,
        message: MessageDTO? = nil,
        eventType: String
    ) async {
        if let conversation {
            await upsertConversations([conversation], source: .delta, eventType: eventType)
        } else if let message {
            await persistRealtimeMessage(message, unreadCount: nil, source: .delta, eventType: eventType)
        }
    }

    static func persistRealtimeMessage(
        _ message: MessageDTO,
        unreadCount: Int?,
        source: MessengerConversationCacheSource = .realtime,
        eventType: String? = nil
    ) async {
        guard MessengerLocalStorageFeatureFlags.isCachedConversationListEnabled else { return }

        let startedAt = Date()
        do {
            try await localStore.patchConversationFromMessage(
                message,
                unreadCount: unreadCount
            )
            try await localStore.upsertLastMessageSnapshot(message)
            MessengerDiagnostics.event(
                .messengerConversationCacheRealtimeApplied,
                conversationID: message.conversationID,
                messageID: message.id,
                metadata: diagnosticMetadata(
                    source: source,
                    eventType: eventType,
                    startedAt: startedAt,
                    hasLastMessage: true
                )
            )
        } catch {
            logUpsertFailed(error: error, source: source, startedAt: startedAt, eventType: eventType)
        }
    }

    static func persistRealtimeConversationRead(conversationID: UUID) async {
        guard MessengerLocalStorageFeatureFlags.isCachedConversationListEnabled else { return }

        let startedAt = Date()
        do {
            try await localStore.patchConversationActivity(
                conversationID: conversationID,
                lastMessageAt: nil,
                unreadCount: 0
            )
            MessengerDiagnostics.event(
                .messengerConversationCacheRealtimeApplied,
                conversationID: conversationID,
                metadata: diagnosticMetadata(source: .realtime, eventType: "conversation.read", startedAt: startedAt)
            )
        } catch {
            logUpsertFailed(error: error, source: .realtime, startedAt: startedAt, eventType: "conversation.read")
        }
    }

    static func persistOutgoingDeliveryStatus(
        conversationID: UUID,
        deliveryStatus: MessageDeliveryStatus
    ) async {
        guard MessengerLocalStorageFeatureFlags.isCachedConversationListEnabled else { return }

        let startedAt = Date()
        do {
            try await localStore.patchConversationOutgoingDeliveryStatus(
                conversationID: conversationID,
                deliveryStatus: deliveryStatus
            )
            MessengerDiagnostics.event(
                .messengerConversationCacheRealtimeApplied,
                conversationID: conversationID,
                metadata: diagnosticMetadata(
                    source: .realtime,
                    eventType: "conversation.receiptPreview",
                    startedAt: startedAt,
                    hasLastMessage: true
                )
            )
        } catch {
            logUpsertFailed(
                error: error,
                source: .realtime,
                startedAt: startedAt,
                eventType: "conversation.receiptPreview"
            )
        }
    }

    static func persistRealtimeConversationUpdated(
        conversationID: UUID,
        lastMessageAt: Date?
    ) async {
        guard MessengerLocalStorageFeatureFlags.isCachedConversationListEnabled else { return }

        let startedAt = Date()
        do {
            try await localStore.patchConversationActivity(
                conversationID: conversationID,
                lastMessageAt: lastMessageAt,
                unreadCount: nil
            )
            MessengerDiagnostics.event(
                .messengerConversationCacheRealtimeApplied,
                conversationID: conversationID,
                metadata: diagnosticMetadata(
                    source: .realtime,
                    eventType: "conversation.updated",
                    startedAt: startedAt,
                    hasLastMessage: lastMessageAt != nil
                )
            )
        } catch {
            logUpsertFailed(error: error, source: .realtime, startedAt: startedAt, eventType: "conversation.updated")
        }
    }

    @discardableResult
    private static func upsertConversations(
        _ conversations: [ConversationDTO],
        source: MessengerConversationCacheSource,
        eventType: String? = nil
    ) async -> Bool {
        guard MessengerLocalStorageFeatureFlags.isCachedConversationListEnabled else { return true }
        guard !conversations.isEmpty else { return true }

        let writeContext = MessengerCacheWriteContext.capture(from: localStore)
        if let reason = writeContext.staleReason(store: localStore) {
            MessengerCacheWriteGuard.logIgnored(reason: reason, context: writeContext, source: source, store: localStore)
            return false
        }

        let startedAt = Date()
        MessengerDiagnostics.event(
            .messengerConversationCacheUpsertStarted,
            metadata: [
                "count": "\(conversations.count)",
                "source": source.rawValue
            ]
        )

        do {
            try await localStore.upsertConversations(conversations)
            if let reason = writeContext.staleReason(store: localStore) {
                MessengerCacheWriteGuard.logIgnored(reason: reason, context: writeContext, source: source, store: localStore)
                return false
            }
            for conversation in conversations {
                if let lastSeenAt = conversation.otherParticipant?.profile.presence?.lastSeenAt,
                   let profileID = conversation.otherParticipant?.profile.id {
                    MessengerDiagnostics.event(
                        .presenceCachePersisted,
                        metadata: [
                            "profileID": MessengerDiagnostics.sanitizeID(profileID),
                            "source": source.rawValue,
                            "hasLastSeenAt": "true",
                            "incomingOnline": "false"
                        ]
                    )
                    _ = lastSeenAt
                }
                if let lastMessage = conversation.lastMessage {
                    try await localStore.upsertLastMessageSnapshot(lastMessage)
                }
            }

            var metadata: [String: String] = [
                "count": "\(conversations.count)",
                "source": source.rawValue,
                "durationMs": "\(durationMilliseconds(since: startedAt))"
            ]
            if let eventType {
                metadata["eventType"] = eventType
            }
            if source == .delta {
                MessengerDiagnostics.event(.messengerConversationCacheDeltaApplied, metadata: metadata)
            } else {
                MessengerDiagnostics.event(.messengerConversationCacheUpsertSucceeded, metadata: metadata)
            }
            return true
        } catch MessengerLocalStoreError.staleSession {
            MessengerCacheWriteGuard.logIgnored(
                reason: "staleSession",
                context: writeContext,
                source: source,
                store: localStore
            )
            return false
        } catch {
            logUpsertFailed(error: error, source: source, startedAt: startedAt, eventType: eventType)
            return false
        }
    }

    private static func logUpsertFailed(
        error: Error,
        source: MessengerConversationCacheSource,
        startedAt: Date,
        eventType: String?
    ) {
        var metadata: [String: String] = [
            "errorCategory": MessengerDiagnostics.sanitizeError(error),
            "source": source.rawValue,
            "durationMs": "\(durationMilliseconds(since: startedAt))"
        ]
        if let eventType {
            metadata["eventType"] = eventType
        }
        MessengerDiagnostics.event(.messengerConversationCacheUpsertFailed, metadata: metadata)
    }

    private static func diagnosticMetadata(
        source: MessengerConversationCacheSource,
        eventType: String?,
        startedAt: Date,
        hasLastMessage: Bool = false
    ) -> [String: String] {
        var metadata: [String: String] = [
            "source": source.rawValue,
            "durationMs": "\(durationMilliseconds(since: startedAt))"
        ]
        if let eventType {
            metadata["eventType"] = eventType
        }
        if hasLastMessage {
            metadata["hasLastMessage"] = "true"
        }
        return metadata
    }

    private static func durationMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
    }
}
