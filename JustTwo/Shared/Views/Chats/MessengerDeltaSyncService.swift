import Foundation

@MainActor
final class MessengerDeltaSyncService {

    static let shared = MessengerDeltaSyncService()

    private let syncState: MessengerSyncStateStore
    private let messageCache: MessageCacheStore
    private let conversationList: ConversationListViewModel
    private let realtimeCoordinator: MessengerRealtimeCoordinator

    private var isInFlight = false
    private var lastSyncStartedAt: Date?
    private var pendingBaselineRevision: Int64?
    private var sessionGeneration = 0

    var onGlobalCursorAdvanced: ((Int64) async -> Void)?
    var autoFullRefreshFallback = true
    private(set) var lastFailureError: Error?
    private(set) var lastRunHadMorePages = false

    private let minimumInterval: TimeInterval = 3

    init(
        syncState: MessengerSyncStateStore? = nil,
        messageCache: MessageCacheStore? = nil,
        conversationList: ConversationListViewModel? = nil,
        realtimeCoordinator: MessengerRealtimeCoordinator? = nil
    ) {
        self.syncState = syncState ?? .shared
        self.messageCache = messageCache ?? .shared
        self.conversationList = conversationList ?? .shared
        self.realtimeCoordinator = realtimeCoordinator ?? .shared
    }

    func prepareBaselineRevision() async throws -> Int64 {
        MessengerDiagnostics.event(.deltaSyncBootstrapStateStarted)
        do {
            let state = try await MessengerSyncService.fetchSyncState()
            pendingBaselineRevision = state.revision
            MessengerDiagnostics.event(
                .deltaSyncBootstrapStateSucceeded,
                metadata: [
                    "revision": "\(state.revision)",
                    "source": "delta"
                ]
            )
            return state.revision
        } catch {
            MessengerDiagnostics.event(
                .deltaSyncBootstrapStateFailed,
                metadata: [
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "source": "delta"
                ]
            )
            throw error
        }
    }

    func finishBaseline(revision: Int64) {
        let baseline = pendingBaselineRevision ?? revision
        syncState.setRevision(baseline)
        pendingBaselineRevision = nil
        MessengerDiagnostics.event(
            .deltaSyncCursorAdvanced,
            metadata: [
                "revision": "\(baseline)",
                "reason": MessengerDeltaSyncReason.bootstrap.rawValue
            ]
        )
        if let onGlobalCursorAdvanced {
            Task { await onGlobalCursorAdvanced(baseline) }
        }
    }

    func syncDeltas(
        reason: MessengerDeltaSyncReason,
        session: SessionStore,
        router: AppRouter
    ) async -> Bool {
        guard !isInFlight else {
            MessengerDiagnostics.event(
                .deltaSyncSkippedAlreadyInFlight,
                metadata: ["reason": reason.rawValue]
            )
            return false
        }

        if shouldThrottle(reason: reason) {
            return false
        }

        guard let afterRevision = syncState.currentRevision else {
            if autoFullRefreshFallback {
                await fullRefreshAndBootstrap(reason: reason, session: session, router: router)
            }
            return false
        }

        let generation = sessionGeneration
        let requestConnectionEpoch = PresenceStore.shared.currentRealtimeConnectionEpoch
        isInFlight = true
        lastSyncStartedAt = Date()
        defer {
            if generation == sessionGeneration {
                isInFlight = false
            }
        }

        guard generation == sessionGeneration else { return false }

        MessengerDiagnostics.event(
            .deltaSyncStarted,
            metadata: [
                "reason": reason.rawValue,
                "afterRevision": "\(afterRevision)"
            ]
        )

        do {
            lastFailureError = nil
            lastRunHadMorePages = false
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            var cursor = afterRevision
            var pageCount = 0

            while pageCount < MessengerSyncEngineLimits.maxPagesPerRun {
                guard generation == sessionGeneration else { return false }

                let page = try await MessengerSyncService.fetchSyncEvents(afterRevision: cursor)
                MessengerDiagnostics.event(
                    .deltaSyncPageFetched,
                    metadata: [
                        "reason": reason.rawValue,
                        "afterRevision": "\(cursor)",
                        "eventCount": "\(page.events.count)",
                        "nextRevision": "\(page.nextRevision)",
                        "hasMore": page.hasMore ? "true" : "false",
                        "pageCount": "\(pageCount + 1)"
                    ]
                )

                try validateRevisionOrder(events: page.events, afterRevision: cursor)

                try await apply(
                    events: page.events,
                    profileID: profileID,
                    session: session,
                    router: router,
                    sessionGeneration: generation,
                    requestConnectionEpoch: requestConnectionEpoch
                )

                guard generation == sessionGeneration else { return false }

                cursor = page.nextRevision
                syncState.advance(to: cursor)
                if let onGlobalCursorAdvanced {
                    await onGlobalCursorAdvanced(cursor)
                }
                MessengerDiagnostics.event(
                    .deltaSyncCursorAdvanced,
                    metadata: [
                        "revision": "\(cursor)",
                        "reason": reason.rawValue
                    ]
                )

                pageCount += 1

                if !page.hasMore {
                    return true
                }

                if pageCount >= MessengerSyncEngineLimits.maxPagesPerRun {
                    lastRunHadMorePages = true
                    return true
                }
            }

            return true
        } catch {
            lastFailureError = error
            MessengerDiagnostics.event(
                .deltaSyncFailed,
                metadata: [
                    "reason": reason.rawValue,
                    "errorCategory": MessengerDiagnostics.sanitizeError(error)
                ]
            )

            if autoFullRefreshFallback, reason != .fullRefreshFallback {
                await fullRefreshAndBootstrap(reason: .fullRefreshFallback, session: session, router: router)
            }
            return false
        }
    }

    func syncConversationRepair(
        conversationID: UUID,
        session: SessionStore,
        router: AppRouter
    ) async -> Bool {
        guard session.isFullyAuthenticated else { return false }

        let generation = sessionGeneration
        let requestConnectionEpoch = PresenceStore.shared.currentRealtimeConnectionEpoch
        let afterRevision = syncState.currentRevision ?? 0

        MessengerDiagnostics.event(
            .syncConversationRepairStarted,
            conversationID: conversationID,
            metadata: [
                "afterRevision": "\(afterRevision)",
                "trigger": MessengerDeltaSyncReason.chatOpened.rawValue
            ]
        )

        do {
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            var cursor = afterRevision
            var pageCount = 0
            var appliedEventCount = 0

            while pageCount < MessengerSyncEngineLimits.maxPagesPerRun {
                guard generation == sessionGeneration else { return false }

                let page = try await MessengerSyncService.fetchSyncEvents(
                    afterRevision: cursor,
                    conversationID: conversationID
                )

                try await apply(
                    events: page.events,
                    profileID: profileID,
                    session: session,
                    router: router,
                    sessionGeneration: generation,
                    requestConnectionEpoch: requestConnectionEpoch
                )
                appliedEventCount += page.events.count
                cursor = page.nextRevision
                pageCount += 1

                if !page.hasMore {
                    break
                }
            }

            MessengerDiagnostics.event(
                .syncConversationRepairApplied,
                conversationID: conversationID,
                metadata: [
                    "eventCount": "\(appliedEventCount)",
                    "pageCount": "\(pageCount)"
                ]
            )
            return true
        } catch {
            MessengerDiagnostics.event(
                .syncApplyFailed,
                conversationID: conversationID,
                metadata: [
                    "errorCode": MessengerDiagnostics.sanitizeError(error),
                    "trigger": MessengerDeltaSyncReason.chatOpened.rawValue
                ]
            )
            return false
        }
    }

    private func validateRevisionOrder(events: [MessengerSyncEventDTO], afterRevision: Int64) throws {
        guard !events.isEmpty else { return }

        let sorted = events.sorted { $0.revision < $1.revision }
        if let first = sorted.first, first.revision > afterRevision + 1 {
            throw MessengerSyncEngineError.revisionGapDetected
        }

        for index in 1..<sorted.count {
            if sorted[index].revision <= sorted[index - 1].revision {
                throw MessengerSyncEngineError.outOfOrderRevision
            }
        }
    }

    func reset() {
        sessionGeneration += 1
        isInFlight = false
        lastSyncStartedAt = nil
        pendingBaselineRevision = nil
        syncState.reset()
    }

    internal var sessionGenerationForTests: Int {
        sessionGeneration
    }

    internal var pendingBaselineRevisionForTests: Int64? {
        pendingBaselineRevision
    }

    internal func setPendingBaselineRevisionForTesting(_ revision: Int64) {
        pendingBaselineRevision = revision
    }

    internal func applyEventsForTesting(
        _ events: [MessengerSyncEventDTO],
        profileID: UUID,
        session: SessionStore,
        router: AppRouter,
        sessionGeneration: Int? = nil,
        requestConnectionEpoch: Int? = nil
    ) async throws {
        try await apply(
            events: events,
            profileID: profileID,
            session: session,
            router: router,
            sessionGeneration: sessionGeneration ?? self.sessionGeneration,
            requestConnectionEpoch: requestConnectionEpoch ?? PresenceStore.shared.currentRealtimeConnectionEpoch
        )
    }

    internal func markSyncStartedForTesting() {
        lastSyncStartedAt = Date()
    }

    internal func wouldThrottleForTests(reason: MessengerDeltaSyncReason) -> Bool {
        shouldThrottle(reason: reason)
    }

    private func shouldThrottle(reason: MessengerDeltaSyncReason) -> Bool {
        switch reason {
        case .realtimeReconnect, .bootstrap, .fullRefreshFallback:
            return false
        case .appForeground, .chatOpened:
            guard let lastSyncStartedAt else { return false }
            return Date().timeIntervalSince(lastSyncStartedAt) < minimumInterval
        }
    }

    private func fullRefreshAndBootstrap(
        reason: MessengerDeltaSyncReason,
        session: SessionStore,
        router: AppRouter
    ) async {
        MessengerDiagnostics.event(
            .deltaSyncFullRefreshFallback,
            metadata: ["reason": reason.rawValue]
        )

        var baselineRevision: Int64?
        do {
            baselineRevision = try await prepareBaselineRevision()
        } catch {
            MessengerDiagnostics.event(
                .deltaSyncBootstrapStateFailed,
                metadata: [
                    "reason": reason.rawValue,
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "phase": "fullRefreshFallbackBeforeRefresh"
                ]
            )
        }

        await conversationList.refreshFromRealtime(session: session, router: router)
        if let activeChat = activeChatViewModel() {
            await activeChat.refreshFromRealtime(session: session, router: router)
        }

        if let baselineRevision {
            finishBaseline(revision: baselineRevision)
            _ = await syncDeltas(reason: .fullRefreshFallback, session: session, router: router)
        }
    }

    private func apply(
        events: [MessengerSyncEventDTO],
        profileID: UUID,
        session: SessionStore,
        router: AppRouter,
        sessionGeneration: Int,
        requestConnectionEpoch: Int
    ) async throws {
        guard !events.isEmpty else { return }
        guard sessionGeneration == self.sessionGeneration else { return }

        MessengerDiagnostics.event(
            .deltaSyncPageApplyStarted,
            metadata: ["eventCount": "\(events.count)"]
        )

        let sorted = events.sorted { $0.revision < $1.revision }
        let activeConversationID = activeChatViewModel()?.conversation.id

        for event in sorted {
            guard sessionGeneration == self.sessionGeneration else {
                MessengerDiagnostics.event(
                    .deltaSyncFailed,
                    metadata: ["reason": "sessionResetDuringApply"]
                )
                return
            }

            if syncState.hasAppliedRevision(event.revision) {
                MessengerDiagnostics.event(
                    .deltaEventSkippedDuplicateRevision,
                    conversationID: event.conversationID,
                    messageID: event.messageID,
                    metadata: [
                        "revision": "\(event.revision)",
                        "type": event.type.rawValue
                    ]
                )
                continue
            }

            MessengerDiagnostics.event(
                .deltaEventReceived,
                conversationID: event.conversationID,
                messageID: event.messageID,
                clientMessageID: event.message?.clientMessageID,
                metadata: [
                    "revision": "\(event.revision)",
                    "type": event.type.rawValue,
                    "source": "delta"
                ]
            )

            applyEvent(
                event,
                profileID: profileID,
                activeConversationID: activeConversationID,
                session: session,
                router: router,
                requestConnectionEpoch: requestConnectionEpoch
            )
            syncState.markRevisionApplied(event.revision)

            MessengerDiagnostics.event(
                .deltaEventApplied,
                conversationID: event.conversationID,
                messageID: event.messageID,
                clientMessageID: event.message?.clientMessageID,
                metadata: [
                    "revision": "\(event.revision)",
                    "type": event.type.rawValue
                ]
            )
        }

        guard sessionGeneration == self.sessionGeneration else { return }

        MessengerDiagnostics.event(
            .deltaSyncPageApplySucceeded,
            metadata: ["eventCount": "\(sorted.count)"]
        )

        for conversationID in Set(sorted.map(\.conversationID)) {
            guard sessionGeneration == self.sessionGeneration else { return }
            MessengerConversationNotification.postMessagesDidChange(conversationID: conversationID)
        }
    }

    private func applyEvent(
        _ event: MessengerSyncEventDTO,
        profileID: UUID,
        activeConversationID: UUID?,
        session: SessionStore,
        router: AppRouter,
        requestConnectionEpoch: Int
    ) {
        switch event.type {
        case .messageCreated, .messageEdited:
            guard let message = event.message else { return }
            logImageDeltaIfNeeded(event: event, message: message, phase: "received")
            applyMessageSnapshot(
                message,
                conversationID: event.conversationID,
                profileID: profileID,
                activeConversationID: activeConversationID,
                session: session,
                router: router,
                eventType: event.type
            )
            if let conversation = event.conversation {
                _ = conversationList.applyDeltaConversation(
                    conversation,
                    currentProfileID: profileID,
                    activeConversationID: activeConversationID,
                    requestConnectionEpoch: requestConnectionEpoch
                )
                MessengerDiagnostics.event(
                    .deltaConversationMerged,
                    conversationID: conversation.id,
                    metadata: ["type": event.type.rawValue]
                )
                persistDeltaConversationCache(
                    conversation: conversation,
                    message: message,
                    eventType: event.type.rawValue
                )
            }

        case .messageDeleted:
            if let message = event.message {
                logImageDeltaIfNeeded(event: event, message: message, phase: "deleted")
                applyMessageSnapshot(
                    message,
                    conversationID: event.conversationID,
                    profileID: profileID,
                    activeConversationID: activeConversationID,
                    session: session,
                    router: router,
                    eventType: event.type
                )
            } else if let messageID = event.messageID {
                applyDeletedMessage(
                    messageID: messageID,
                    conversationID: event.conversationID,
                    deletedAt: event.occurredAt,
                    activeConversationID: activeConversationID
                )
            }
            if let conversation = event.conversation {
                _ = conversationList.applyDeltaConversation(
                    conversation,
                    currentProfileID: profileID,
                    activeConversationID: activeConversationID,
                    requestConnectionEpoch: requestConnectionEpoch
                )
                persistDeltaConversationCache(
                    conversation: conversation,
                    message: event.message,
                    eventType: event.type.rawValue
                )
            }

        case .reactionAdded, .reactionRemoved:
            guard let message = event.message else { return }
            applyMessageSnapshot(
                message,
                conversationID: event.conversationID,
                profileID: profileID,
                activeConversationID: activeConversationID,
                session: session,
                router: router,
                eventType: event.type
            )
            MessengerDiagnostics.event(
                .deltaReactionApplied,
                conversationID: event.conversationID,
                messageID: message.id,
                metadata: ["type": event.type.rawValue]
            )

        case .conversationRead:
            applyReceiptEvent(
                event,
                status: .read,
                profileID: profileID,
                activeConversationID: activeConversationID
            )
            if let conversation = event.conversation {
                _ = conversationList.applyDeltaConversation(
                    conversation,
                    currentProfileID: profileID,
                    activeConversationID: activeConversationID,
                    requestConnectionEpoch: requestConnectionEpoch
                )
                persistDeltaConversationCache(
                    conversation: conversation,
                    message: event.message,
                    eventType: event.type.rawValue
                )
            }

        case .conversationDelivered:
            applyReceiptEvent(
                event,
                status: .delivered,
                profileID: profileID,
                activeConversationID: activeConversationID
            )
            if let conversation = event.conversation {
                _ = conversationList.applyDeltaConversation(
                    conversation,
                    currentProfileID: profileID,
                    activeConversationID: activeConversationID,
                    requestConnectionEpoch: requestConnectionEpoch
                )
                persistDeltaConversationCache(
                    conversation: conversation,
                    message: event.message,
                    eventType: event.type.rawValue
                )
            }

        case .conversationUpdated:
            if let conversation = event.conversation {
                _ = conversationList.applyDeltaConversation(
                    conversation,
                    currentProfileID: profileID,
                    activeConversationID: activeConversationID,
                    requestConnectionEpoch: requestConnectionEpoch
                )
                MessengerDiagnostics.event(
                    .deltaConversationMerged,
                    conversationID: conversation.id,
                    metadata: ["type": event.type.rawValue]
                )
                persistDeltaConversationCache(
                    conversation: conversation,
                    message: event.message,
                    eventType: event.type.rawValue
                )
            }
        }
    }

    private func persistDeltaConversationCache(
        conversation: ConversationDTO,
        message: MessageDTO?,
        eventType: String
    ) {
        Task {
            await MessengerConversationCacheService.persistDeltaConversation(
                conversation,
                message: message,
                eventType: eventType
            )
        }
    }

    private func applyMessageSnapshot(
        _ message: MessageDTO,
        conversationID: UUID,
        profileID: UUID,
        activeConversationID: UUID?,
        session: SessionStore,
        router: AppRouter,
        eventType: MessengerSyncEventType
    ) {
        if activeConversationID == conversationID,
           let chat = activeChatViewModel() {
            let inserted = chat.applyRealtimeMessage(message, currentProfileID: profileID)
            if eventType == .messageCreated, message.senderProfileID == profileID {
                _ = conversationList.applyOutgoingConfirmed(
                    conversationID: conversationID,
                    message: message,
                    currentProfileID: profileID
                )
            } else {
                _ = conversationList.applyRealtimeMessage(
                    message,
                    currentProfileID: profileID,
                    activeConversationID: activeConversationID,
                    router: router
                )
            }
            if message.clientMessageID != nil, message.senderProfileID == profileID {
                MessengerDiagnostics.event(
                    .deltaOptimisticImageReconciled,
                    conversationID: conversationID,
                    messageID: message.id,
                    clientMessageID: message.clientMessageID,
                    metadata: [
                        "reconciled": inserted ? "true" : "false",
                        "kind": message.kind.rawValue
                    ]
                )
            }
            logImageDeltaIfNeeded(eventType: eventType, message: message, phase: "merged")
            MessengerDiagnostics.event(
                .deltaMessageMerged,
                conversationID: conversationID,
                messageID: message.id,
                clientMessageID: message.clientMessageID,
                metadata: [
                    "type": eventType.rawValue,
                    "kind": message.kind.rawValue,
                    "target": "activeChat"
                ]
            )
            persistDeltaMessageCache(message, eventType: eventType.rawValue)
            if eventType == .messageCreated {
                // Active-chat path: apply completed above before scheduling ack.
                scheduleDeliveryAckIfNeeded(
                    message: message,
                    conversationID: conversationID,
                    profileID: profileID,
                    session: session,
                    router: router,
                    source: "sync"
                )
            }
            return
        }

        let applied = messageCache.applyRealtimeMessage(
            message,
            conversationID: conversationID,
            currentProfileID: profileID
        )
        _ = conversationList.applyRealtimeMessage(
            message,
            currentProfileID: profileID,
            activeConversationID: activeConversationID,
            router: router
        )
        if message.clientMessageID != nil, message.senderProfileID == profileID {
            MessengerDiagnostics.event(
                .deltaOptimisticImageReconciled,
                conversationID: conversationID,
                messageID: message.id,
                clientMessageID: message.clientMessageID,
                metadata: [
                    "reconciled": applied ? "true" : "false",
                    "kind": message.kind.rawValue
                ]
            )
        }
        logImageDeltaIfNeeded(eventType: eventType, message: message, phase: applied ? "merged" : "deduped")
        MessengerDiagnostics.event(
            applied ? .deltaMessageMerged : .deltaEventSkippedDuplicateRevision,
            conversationID: conversationID,
            messageID: message.id,
            clientMessageID: message.clientMessageID,
            metadata: [
                "type": eventType.rawValue,
                "kind": message.kind.rawValue,
                "target": "cache"
            ]
        )
        persistDeltaMessageCache(message, eventType: eventType.rawValue)
        if eventType == .messageCreated {
            // Ack only after local apply/dedup attempt completed. Coordinator + backend
            // keep boundary monotonic for duplicates.
            scheduleDeliveryAckIfNeeded(
                message: message,
                conversationID: conversationID,
                profileID: profileID,
                session: session,
                router: router,
                source: "sync"
            )
        }
    }

    private func scheduleDeliveryAckIfNeeded(
        message: MessageDTO,
        conversationID: UUID,
        profileID: UUID,
        session: SessionStore,
        router: AppRouter,
        source: String
    ) {
        guard message.deletedAt == nil else { return }
        guard message.senderProfileID != profileID else { return }
        guard session.isFullyAuthenticated else {
            MessengerDiagnostics.event(
                .deliveredAckSkipped,
                conversationID: conversationID,
                messageID: message.id,
                metadata: ["reason": "unauthenticated", "source": source]
            )
            return
        }

        MessengerDiagnostics.event(
            .deliveryMessageObserved,
            conversationID: conversationID,
            messageID: message.id,
            metadata: [
                "source": source,
                "isAppForeground": "\(MessengerSessionSupport.isAppForegroundActive)"
            ]
        )
        MessengerDiagnostics.event(
            .deliveryAckScheduled,
            conversationID: conversationID,
            messageID: message.id,
            metadata: ["source": source]
        )

        Task { @MainActor in
            await ConversationDeliveryAckCoordinator.shared.acknowledgeDeliveredIfNeeded(
                conversationID: conversationID,
                message: message,
                currentProfileID: profileID,
                session: session,
                router: router,
                source: source
            )
        }
    }

    private func persistDeltaMessageCache(_ message: MessageDTO, eventType: String) {
        Task {
            await MessengerMessageCacheService.persistDeltaMessage(message, eventType: eventType)
        }
    }

    private func applyDeletedMessage(
        messageID: UUID,
        conversationID: UUID,
        deletedAt: Date?,
        activeConversationID: UUID?
    ) {
        let payload = MessageDeletedPayload(
            messageID: messageID,
            deletedAt: deletedAt,
            isDeleted: true
        )

        if activeConversationID == conversationID,
           let chat = activeChatViewModel() {
            _ = chat.applyRealtimeDeletedMessage(payload)
        } else {
            _ = messageCache.markMessageDeleted(
                conversationID: conversationID,
                messageID: messageID,
                deletedAt: deletedAt
            )
        }

        MessengerDiagnostics.event(
            .deltaDeleteApplied,
            conversationID: conversationID,
            messageID: messageID,
            metadata: ["source": "delta"]
        )
        MessengerDiagnostics.event(
            .deltaImageDeletedClearedAttachments,
            conversationID: conversationID,
            messageID: messageID,
            metadata: ["source": "delta"]
        )
        Task {
            await MessengerMessageCacheService.persistMessageDeleted(
                messageID: messageID,
                deletedAt: deletedAt
            )
        }
    }

    private func applyReceiptEvent(
        _ event: MessengerSyncEventDTO,
        status: MessageDeliveryStatus,
        profileID: UUID,
        activeConversationID: UUID?
    ) {
        guard let receipt = event.receipt else { return }
        guard receipt.profileID != profileID else {
            _ = conversationList.applyRealtimeConversationRead(
                conversationID: event.conversationID,
                profileID: receipt.profileID,
                currentProfileID: profileID
            )
            return
        }

        let cutoffDate = status == .read ? receipt.readAt : receipt.deliveredAt
        let messageID = receipt.messageID ?? event.messageID

        if activeConversationID == event.conversationID,
           let chat = activeChatViewModel() {
            _ = chat.applyDeliveryStatus(status, messageID: messageID, cutoffDate: cutoffDate)
        } else {
            _ = messageCache.applyDeliveryStatus(
                conversationID: event.conversationID,
                status: status,
                messageID: messageID,
                cutoffDate: cutoffDate
            )
        }

        MessengerDiagnostics.event(
            .deltaReceiptApplied,
            conversationID: event.conversationID,
            messageID: messageID,
            metadata: [
                "type": event.type.rawValue,
                "status": status.rawValue
            ]
        )
        if let receipt = event.receipt {
            Task {
                await MessengerMessageCacheService.persistReceipt(
                    receipt,
                    eventType: event.type.rawValue
                )
            }
        }
    }

    private func logImageDeltaIfNeeded(
        event: MessengerSyncEventDTO? = nil,
        eventType: MessengerSyncEventType? = nil,
        message: MessageDTO,
        phase: String
    ) {
        guard message.kind == .image else { return }

        let type = eventType ?? event?.type
        MessengerDiagnostics.event(
            .deltaImageMessageReceived,
            conversationID: message.conversationID,
            messageID: message.id,
            clientMessageID: message.clientMessageID,
            metadata: [
                "phase": phase,
                "type": type?.rawValue ?? "unknown"
            ]
        )

        if message.deletedAt != nil || message.attachments.isEmpty {
            MessengerDiagnostics.event(
                .deltaImageDeletedClearedAttachments,
                conversationID: message.conversationID,
                messageID: message.id,
                metadata: ["phase": phase]
            )
            return
        }

        guard let attachment = message.attachments.first else {
            MessengerDiagnostics.event(
                .deltaImageDownloadURLMissing,
                conversationID: message.conversationID,
                messageID: message.id,
                metadata: ["phase": phase]
            )
            return
        }

        MessengerDiagnostics.event(
            .deltaImageAttachmentDecoded,
            conversationID: message.conversationID,
            messageID: message.id,
            metadata: [
                "phase": phase,
                "attachmentID": attachment.id.uuidString,
                "contentType": attachment.contentType,
                "byteSize": "\(attachment.byteSize)",
                "width": "\(attachment.width)",
                "height": "\(attachment.height)"
            ]
        )

        MessengerDiagnostics.event(
            attachment.downloadUrl == nil ? .deltaImageDownloadURLMissing : .deltaImageDownloadURLPresent,
            conversationID: message.conversationID,
            messageID: message.id,
            metadata: [
                "phase": phase,
                "attachmentID": attachment.id.uuidString,
                "downloadPresent": attachment.downloadUrl == nil ? "false" : "true"
            ]
        )
    }

    private func activeChatViewModel() -> ChatViewModel? {
        realtimeCoordinator.activeChatForDeltaSync
    }
}
