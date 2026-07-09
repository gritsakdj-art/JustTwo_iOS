import Foundation

struct MessengerDiagnosticEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let event: String
    let conversationID: UUID?
    let messageID: UUID?
    let clientMessageID: String?
    let metadata: [String: String]

    nonisolated var exportLine: String {
        var parts = [
            "timestamp=\(timestamp.ISO8601Format())",
            "event=\(event)"
        ]

        if let conversationID {
            parts.append("conversationID=\(conversationID.uuidString)")
        }
        if let messageID {
            parts.append("messageID=\(messageID.uuidString)")
        }
        if let clientMessageID {
            parts.append("clientMessageID=\(clientMessageID)")
        }

        for key in metadata.keys.sorted() {
            guard let value = metadata[key] else { continue }
            parts.append("\(key)=\(value)")
        }

        return parts.joined(separator: " ")
    }
}

@MainActor
final class MessengerDiagnosticsStore {
    static let shared = MessengerDiagnosticsStore()

    private(set) var events: [MessengerDiagnosticEntry] = []
    let limit: Int

    init(limit: Int = 300) {
        self.limit = max(1, limit)
    }

    func append(_ entry: MessengerDiagnosticEntry) {
        events.append(entry)
        if events.count > limit {
            events.removeFirst(events.count - limit)
        }
    }

    func clear() {
        events.removeAll()
    }

    func exportText() -> String {
        events.map(\.exportLine).joined(separator: "\n")
    }
}

enum MessengerDiagnosticEvent: String, Sendable {
    case conversationRowTapped
    case navigationRequested
    case activeConversationChanged

    case chatAppeared
    case chatDisappeared
    case chatOpenStarted
    case chatOpenCompleted
    case chatCloseStarted
    case chatCloseCompleted

    case loadMessagesStarted
    case loadMessagesSucceeded
    case loadMessagesFailed
    case loadMessagesCancelled
    case loadMessagesIgnoredStaleGeneration
    case loadSkippedInFlight

    case chatInitialCacheSync
    case chatInitialLoadRequested
    case chatInitialLoadSkippedInFlight
    case chatInitialLoadApplied
    case chatInitialLoadNoMessages
    case chatInitialLoadIgnoredStaleGeneration
    case chatCacheNotificationReceived

    case sendStarted
    case sendSucceeded
    case sendFailed
    case sendCancelled
    case sendSkippedAlreadySending
    case draftRestoredAfterFailure
    case draftRestoreSkippedUserTypedNewText

    case deliveredAckSent
    case deliveredAckSkipped
    case deliveredAckFailed

    case readAckSent
    case readAckSkipped
    case readAckFailed

    case realtimeEventReceived
    case realtimeEventApplied
    case realtimeEventSkipped
    case realtimeEventFallbackRefresh

    case cacheMergeStarted
    case cacheMergeCompleted
    case cacheMergePreservedRealtimeState

    case scrollInitialTargetSelected
    case scrollToBottomRequested
    case scrollToBottomCompleted
    case scrollSkipped
    case keyboardHeightChanged
    case keyboardBottomStickRequested
    case isSendingReset

    case initialPositioningStarted
    case initialPositioningCompleted
    case initialPositioningSkipped
    case runtimeAutoScrollRequested
    case runtimeAutoScrollSkipped
    case scrollPhase

    case outboxEnqueued
    case optimisticMessageInserted
    case outboxSendStarted
    case outboxSendSucceeded
    case outboxSendFailed
    case outboxRetryRequested
    case outboxRetrySkippedAlreadySending
    case outboxReconciledFromREST
    case outboxReconciledFromRealtime
    case outboxPreservedDuringFetch
    case outboxClearedOnLogout
    case outboxItemCreated
    case outboxRetryScheduled
    case outboxManualRetry
    case outboxItemCleared
    case outboxReset
    case outboxRehydrated

    case imagePicked
    case imagePrepareStarted
    case imagePrepareSucceeded
    case imagePrepareFailed
    case imageUploadURLRequested
    case imageUploadURLSucceeded
    case imageUploadURLFailed
    case imageUploadStarted
    case imageUploadSucceeded
    case imageUploadFailed
    case imageMessageCreateStarted
    case imageMessageCreateSucceeded
    case imageMessageCreateFailed
    case imageOutboxRetryRequested
    case imageTempFileCleaned

    case outboxImageComposerPreviewSelected
    case outboxImageComposerPreviewRemoved
    case outboxImageItemCreated
    case outboxPendingMediaStored
    case outboxImageUploadStarted
    case outboxImageUploadSucceeded
    case outboxImageUploadFailed
    case outboxImageCreateMessageStarted
    case outboxImageCreateMessageSucceeded
    case outboxImageCreateMessageFailed
    case outboxImageRehydrated
    case outboxPendingMediaCleared
    case outboxPendingMediaMissing
    case outboxImageRetryScheduled

    case outboxRetryTapped
    case outboxCancelTapped
    case outboxAutoRetryScheduled
    case outboxNetworkRestored
    case outboxNetworkUnavailable
    case outboxRetrySkipped
    case outboxStateChanged
    case outboxStaleSendingRecovered
    case outboxProcessorStarted
    case outboxProcessorFinished
    case outboxProcessorItemFailed
    case outboxProcessorItemSucceeded

    case imageBubbleRenderStarted
    case imageBubbleRenderSucceeded
    case imageBubbleRenderFailed
    case imageBubbleUsedLocalFile
    case imageBubbleUsedRemoteURL
    case imageCacheHit
    case imageCacheMiss

    case deltaSyncBootstrapStateStarted
    case deltaSyncBootstrapStateSucceeded
    case deltaSyncBootstrapStateFailed
    case deltaSyncStarted
    case deltaSyncPageFetched
    case deltaSyncPageApplyStarted
    case deltaSyncPageApplySucceeded
    case deltaSyncPageApplyFailed
    case deltaSyncCursorAdvanced
    case deltaSyncSkippedAlreadyInFlight
    case deltaSyncFailed
    case deltaSyncFullRefreshFallback

    case deltaEventReceived
    case deltaEventApplied
    case deltaEventSkippedDuplicateRevision
    case deltaMessageMerged
    case deltaConversationMerged
    case deltaReceiptApplied
    case deltaReactionApplied
    case deltaDeleteApplied

    case deltaImageMessageReceived
    case deltaImageAttachmentDecoded
    case deltaImageMessageMerged
    case deltaImageMessageDeduped
    case deltaImageDeletedClearedAttachments
    case deltaImageDownloadURLPresent
    case deltaImageDownloadURLMissing
    case deltaImageBubbleSourceSelected
    case deltaImageCacheHit
    case deltaImageCacheMiss
    case deltaImageRenderFailed
    case deltaOptimisticImageReconciled

    case messengerLocalStoreInitialized
    case messengerLocalStoreResetStarted
    case messengerLocalStoreResetSucceeded
    case messengerLocalStoreResetFailed
    case messengerLocalConversationUpserted
    case messengerLocalMessagesUpserted
    case messengerLocalMessageDeleted
    case messengerLocalReceiptApplied
    case messengerLocalSyncMetadataUpdated
    case messengerLocalMappingFailed

    case messengerSwiftDataContainerLoadFailed
    case messengerSwiftDataContainerRecoveredAfterSchemaMismatch

    case messengerConversationCacheLoadStarted
    case messengerConversationCacheLoadSucceeded
    case messengerConversationCacheLoadFailed
    case messengerConversationCacheHydratedUI
    case messengerConversationCacheEmpty
    case messengerConversationCacheNetworkRefreshStarted
    case messengerConversationCacheNetworkRefreshSucceeded
    case messengerConversationCacheNetworkRefreshFailed
    case messengerConversationCacheUpsertStarted
    case messengerConversationCacheUpsertSucceeded
    case messengerConversationCacheUpsertFailed
    case messengerConversationCacheDeltaApplied
    case messengerConversationCacheRealtimeApplied
    case messengerConversationCacheSkippedStale

    case messengerMessageCacheHydrateStarted
    case messengerMessageCacheHydrateSucceeded
    case messengerMessageCacheHydrateFailed
    case messengerMessageCacheHydratedUI
    case messengerMessageCacheEmpty
    case messengerMessageNetworkRefreshStarted
    case messengerMessageNetworkRefreshSucceeded
    case messengerMessageNetworkRefreshFailed
    case messengerMessagePaginationStarted
    case messengerMessagePaginationSucceeded
    case messengerMessagePaginationFailed
    case messengerMessageCacheUpsertStarted
    case messengerMessageCacheUpsertSucceeded
    case messengerMessageCacheUpsertFailed
    case messengerMessageDeltaPersisted
    case messengerMessageRealtimePersisted
    case messengerMessageLoadCancelled
    case messengerMessageLoadStaleIgnored
    case messengerMessageLoadingStateRecovered
    case messengerMessageFallbackToCache

    case messengerStartupMessagesLocalPreloadStarted
    case messengerStartupMessagesLocalPreloadSucceeded
    case messengerStartupMessagesLocalPreloadEmpty
    case messengerStartupMessagesNetworkPreloadSkippedFreshCache
    case messengerStartupMessagesNetworkPreloadStarted
    case messengerStartupMessagesNetworkPreloadSucceeded
    case messengerStartupMessagesNetworkPreloadFailed

    case messengerChatOpenNetworkRefreshSkippedFreshCache
    case messengerChatOpenNetworkRefreshSkippedInFlight
    case messengerChatOpenNetworkRefreshStarted
    case messengerChatOpenNetworkRefreshSucceeded
    case messengerChatOpenNetworkRefreshFailed

    case messengerConversationRefreshSkippedChatPop
    case messengerConversationRefreshSkippedRecent
    case messengerConversationRefreshForcedManual

    case messengerNetworkRequestSkippedOffline
    case messengerRequestSingleFlightJoined

    case messengerDeliveryAckScheduled
    case messengerDeliveryAckSucceeded
    case messengerDeliveryAckFailed
    case messengerReadAckScheduled
    case messengerReadAckSucceeded
    case messengerReadAckFailed

    case messengerMediaDiskCacheLookupStarted
    case messengerMediaDiskCacheHit
    case messengerMediaDiskCacheMiss
    case messengerMediaDiskCacheReadFailed
    case messengerMediaDiskCacheStoreStarted
    case messengerMediaDiskCacheStoreSucceeded
    case messengerMediaDiskCacheStoreFailed
    case messengerMediaDiskCacheRemoved
    case messengerMediaDiskCacheCleanupStarted
    case messengerMediaDiskCacheCleanupSucceeded
    case messengerMediaDiskCacheCleanupFailed
    case messengerMediaDiskCacheBackupExcluded
    case messengerMediaDiskCacheFileProtectionApplied

    case startupSessionSnapshotLoadStarted
    case startupSessionSnapshotLoadSucceeded
    case startupSessionSnapshotLoadFailed
    case startupSessionSnapshotSaved
    case startupSessionSnapshotCleared

    case splashTokenFound
    case splashTokenMissing
    case splashTokenExpiredLocal
    case splashNetworkValidationStarted
    case splashNetworkValidationSucceeded
    case splashNetworkValidationFailedRecoverable
    case splashNetworkValidationFailedAuth
    case splashOfflineCachedSessionAccepted
    case splashOfflineCachedSessionRejected
    case splashRouteMainFromCache
    case splashRouteMainFromNetwork
    case splashRouteAuth
    case splashRouteProfileSetup

    case startupCriticalLocalWarmupStarted
    case startupCriticalLocalWarmupSucceeded
    case startupBackgroundNetworkWarmupScheduled
    case startupBackgroundNetworkWarmupSucceeded
    case startupBackgroundNetworkWarmupFailed

    case startupSkippedNetworkCriticalBecauseCacheAvailable
    case startupProfilePhotosDeferred
    case startupConversationAvatarsDeferred
}

enum MessengerDiagnostics {
    static let emptyExportText = "Messenger diagnostics is empty."

    nonisolated static func event(
        _ name: MessengerDiagnosticEvent,
        conversationID: UUID? = nil,
        messageID: UUID? = nil,
        clientMessageID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        let entry = makeEntry(
            name,
            conversationID: conversationID,
            messageID: messageID,
            clientMessageID: clientMessageID,
            metadata: metadata
        )

        NetworkDebug.log("Messenger diagnostic \(entry.exportLine)")

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                MessengerDiagnosticsStore.shared.append(entry)
            }
        } else {
            Task { @MainActor in
                MessengerDiagnosticsStore.shared.append(entry)
            }
        }
    }

    @MainActor
    static func exportTextForClipboard() -> String {
        exportTextForClipboard(from: MessengerDiagnosticsStore.shared)
    }

    @MainActor
    static func exportTextForClipboard(from store: MessengerDiagnosticsStore) -> String {
        let exportText = store.exportText()
        guard !exportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return emptyExportText
        }
        return exportText
    }

    nonisolated static func makeEntry(
        _ name: MessengerDiagnosticEvent,
        conversationID: UUID? = nil,
        messageID: UUID? = nil,
        clientMessageID: String? = nil,
        metadata: [String: String] = [:],
        timestamp: Date = Date(),
        id: UUID = UUID()
    ) -> MessengerDiagnosticEntry {
        MessengerDiagnosticEntry(
            id: id,
            timestamp: timestamp,
            event: name.rawValue,
            conversationID: conversationID,
            messageID: messageID,
            clientMessageID: sanitizedClientMessageID(clientMessageID),
            metadata: sanitizedMetadata(metadata)
        )
    }

    nonisolated static func sanitizeID(_ id: UUID) -> String {
        let value = id.uuidString
        guard value.count > 8 else { return value }
        return String(value.prefix(8)) + "..."
    }

    static func sanitizeError(_ error: Error) -> String {
        if error is CancellationError {
            return "cancelled"
        }

        let networkError = NetworkError.map(error)
        switch networkError {
        case .cancelled:
            return "cancelled"
        case .noInternet, .connectionLost, .tlsFailure, .serverUnavailable:
            return "network"
        case .timeout:
            return "timeout"
        case .unauthorized:
            return "unauthorized"
        case .httpError(let statusCode, _):
            if statusCode == 401 {
                return "unauthorized"
            }
            if statusCode == 404 {
                return "notFound"
            }
            if statusCode >= 500 {
                return "server"
            }
            return "http\(statusCode)"
        case .decodingError:
            return "decoding"
        case .invalidResponse:
            return "invalidResponse"
        case .unknown:
            return "unknown"
        }
    }

    nonisolated static func sanitizedMetadata(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { result, pair in
            let key = sanitizeToken(pair.key, fallback: "metadata")
            guard !isSensitiveMetadataKey(key) else { return }
            result[key] = sanitizeToken(pair.value, fallback: "redacted")
        }
    }

    nonisolated private static func sanitizedClientMessageID(_ value: String?) -> String? {
        value.map { sanitizeToken($0, fallback: "clientMessageID") }
    }

    nonisolated private static func sanitizeToken(_ value: String, fallback: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return fallback }

        let maxLength = 160
        if collapsed.count <= maxLength {
            return collapsed
        }

        let index = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<index]) + "...truncated"
    }

    nonisolated private static func isSensitiveMetadataKey(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        let allowedKeys: Set<String> = [
            "downloadpresent",
            "hasdownloadurl",
            "hasuploadurl"
        ]
        if allowedKeys.contains(lowercased) {
            return false
        }

        let sensitiveFragments = [
            "authorization",
            "jwt",
            "token",
            "password",
            "email",
            "displayname",
            "body",
            "caption",
            "comment",
            "draft",
            "text",
            "payload",
            "raw",
            "url",
            "storagekey",
            "localpath",
            "filepath"
        ]

        return sensitiveFragments.contains { lowercased.contains($0) }
    }
}
