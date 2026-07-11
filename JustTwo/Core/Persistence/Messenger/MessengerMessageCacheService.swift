import Foundation

enum MessengerMessageCacheSource: String, Sendable {
    case cache
    case rest
    case delta
    case realtime
    case pagination
}

@MainActor
enum MessengerMessageCacheService {

    #if DEBUG
    static var testingStore: MessengerLocalStore?
    /// When non-empty, `persistDeltaMessage` returns false for matching message IDs.
    static var testingFailPersistForMessageIDs: Set<UUID> = []
    #endif

    private static var localStore: MessengerLocalStore {
        #if DEBUG
        if let testingStore {
            return testingStore
        }
        #endif
        return .shared
    }

    static func hydrateCachedMessages(
        conversationID: UUID,
        currentProfileID: UUID,
        limit: Int
    ) async -> [ChatMessage]? {
        guard MessengerLocalStorageFeatureFlags.isLocalReadEnabled else { return nil }

        let startedAt = Date()
        MessengerDiagnostics.event(
            .messengerMessageCacheHydrateStarted,
            conversationID: conversationID
        )

        do {
            let snapshots = try await localStore.fetchLocalMessages(
                conversationID: conversationID,
                limit: limit,
                before: nil
            )
            guard !snapshots.isEmpty else {
                MessengerDiagnostics.event(
                    .messengerMessageCacheEmpty,
                    conversationID: conversationID,
                    metadata: ["durationMs": "\(durationMilliseconds(since: startedAt))"]
                )
                return nil
            }

            let messages = snapshots
                .reversed()
                .map { ChatUIMapping.message(from: $0, currentProfileID: currentProfileID) }

            MessengerDiagnostics.event(
                .messengerMessageCacheHydrateSucceeded,
                conversationID: conversationID,
                metadata: [
                    "count": "\(messages.count)",
                    "durationMs": "\(durationMilliseconds(since: startedAt))",
                    "source": MessengerMessageCacheSource.cache.rawValue
                ]
            )
            return messages
        } catch {
            MessengerDiagnostics.event(
                .messengerMessageCacheHydrateFailed,
                conversationID: conversationID,
                metadata: [
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "durationMs": "\(durationMilliseconds(since: startedAt))"
                ]
            )
            return nil
        }
    }

    @discardableResult
    static func persistRESTMessages(
        _ messages: [MessageDTO],
        conversationID: UUID
    ) async -> Bool {
        await upsertMessages(messages, conversationID: conversationID, source: .rest)
    }

    @discardableResult
    static func persistPaginationMessages(
        _ messages: [MessageDTO],
        conversationID: UUID
    ) async -> Bool {
        await upsertMessages(messages, conversationID: conversationID, source: .pagination)
    }

    @discardableResult
    static func persistDeltaMessage(
        _ message: MessageDTO,
        eventType: String
    ) async -> Bool {
        #if DEBUG
        if testingFailPersistForMessageIDs.contains(message.id) {
            return false
        }
        #endif
        return await upsertMessages([message], conversationID: message.conversationID, source: .delta, eventType: eventType)
    }

    @discardableResult
    static func persistRealtimeMessage(
        _ message: MessageDTO,
        eventType: String?
    ) async -> Bool {
        await upsertMessages(
            [message],
            conversationID: message.conversationID,
            source: .realtime,
            eventType: eventType
        )
    }

    static func persistMessageDeleted(messageID: UUID, deletedAt: Date?) async {
        let startedAt = Date()
        do {
            try await localStore.markMessageDeleted(messageID: messageID, deletedAt: deletedAt)
            MessengerDiagnostics.event(
                .messengerMessageDeltaPersisted,
                messageID: messageID,
                metadata: [
                    "eventType": "message.deleted",
                    "durationMs": "\(durationMilliseconds(since: startedAt))"
                ]
            )
        } catch {
            logUpsertFailed(
                error: error,
                source: .delta,
                startedAt: startedAt,
                eventType: "message.deleted",
                conversationID: nil
            )
        }
    }

    static func persistReactions(from message: MessageDTO) async {
        let startedAt = Date()
        do {
            try await localStore.upsertReactions(from: message)
            MessengerDiagnostics.event(
                .messengerMessageDeltaPersisted,
                conversationID: message.conversationID,
                messageID: message.id,
                metadata: [
                    "eventType": "reaction.updated",
                    "durationMs": "\(durationMilliseconds(since: startedAt))"
                ]
            )
        } catch {
            logUpsertFailed(
                error: error,
                source: .delta,
                startedAt: startedAt,
                eventType: "reaction.updated",
                conversationID: message.conversationID
            )
        }
    }

    static func persistReceipt(_ receipt: MessengerReceiptDTO, eventType: String) async {
        let startedAt = Date()
        do {
            try await localStore.applyReceipt(receipt)
            MessengerDiagnostics.event(
                .messengerMessageDeltaPersisted,
                conversationID: receipt.conversationID,
                metadata: [
                    "eventType": eventType,
                    "durationMs": "\(durationMilliseconds(since: startedAt))"
                ]
            )
        } catch {
            logUpsertFailed(
                error: error,
                source: .delta,
                startedAt: startedAt,
                eventType: eventType,
                conversationID: receipt.conversationID
            )
        }
    }

    @discardableResult
    private static func upsertMessages(
        _ messages: [MessageDTO],
        conversationID: UUID,
        source: MessengerMessageCacheSource,
        eventType: String? = nil
    ) async -> Bool {
        guard !messages.isEmpty else { return true }

        let startedAt = Date()
        MessengerDiagnostics.event(
            .messengerMessageCacheUpsertStarted,
            conversationID: conversationID,
            metadata: [
                "count": "\(messages.count)",
                "source": source.rawValue
            ]
        )

        do {
            try await localStore.upsertMessages(messages, conversationID: conversationID)

            var metadata: [String: String] = [
                "count": "\(messages.count)",
                "source": source.rawValue,
                "durationMs": "\(durationMilliseconds(since: startedAt))",
                "hasAttachments": messages.contains { !$0.attachments.isEmpty } ? "true" : "false",
                "attachmentCount": "\(messages.reduce(0) { $0 + $1.attachments.count })"
            ]
            if let eventType {
                metadata["eventType"] = eventType
            }

            switch source {
            case .delta:
                MessengerDiagnostics.event(.messengerMessageDeltaPersisted, conversationID: conversationID, metadata: metadata)
            case .realtime:
                MessengerDiagnostics.event(.messengerMessageRealtimePersisted, conversationID: conversationID, metadata: metadata)
            default:
                MessengerDiagnostics.event(.messengerMessageCacheUpsertSucceeded, conversationID: conversationID, metadata: metadata)
            }
            return true
        } catch {
            logUpsertFailed(
                error: error,
                source: source,
                startedAt: startedAt,
                eventType: eventType,
                conversationID: conversationID
            )
            return false
        }
    }

    private static func logUpsertFailed(
        error: Error,
        source: MessengerMessageCacheSource,
        startedAt: Date,
        eventType: String?,
        conversationID: UUID?
    ) {
        var metadata: [String: String] = [
            "errorCategory": MessengerDiagnostics.sanitizeError(error),
            "source": source.rawValue,
            "durationMs": "\(durationMilliseconds(since: startedAt))"
        ]
        if let eventType {
            metadata["eventType"] = eventType
        }
        MessengerDiagnostics.event(.messengerMessageCacheUpsertFailed, conversationID: conversationID, metadata: metadata)
    }

    private static func durationMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
    }
}
