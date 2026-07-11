import Foundation

@MainActor
final class MessengerRealtimeCoordinator {

    static let shared = MessengerRealtimeCoordinator()

    private weak var activeChatViewModel: ChatViewModel?
    private weak var conversationListViewModel: ConversationListViewModel?
    private weak var session: SessionStore?
    private weak var router: AppRouter?

    private let realtimeClient: RealtimeClient
    private let eventRouter: RealtimeEventRouter
    private let presenceStore: PresenceStore
    private var eventTask: Task<Void, Never>?
    private var activeConversationID: UUID?
    private var subscribedConversationID: UUID?
    private var conversationListSubscriptionIDs: Set<UUID> = []
    private var isRefreshingAfterReconnect = false
    private var connectAndSyncGeneration = 0
    private var conversationFallbackRefreshTask: Task<Void, Never>?
    private var activeChatFallbackRefreshTask: Task<Void, Never>?

    init(
        realtimeClient: RealtimeClient,
        eventRouter: RealtimeEventRouter,
        presenceStore: PresenceStore
    ) {
        self.realtimeClient = realtimeClient
        self.eventRouter = eventRouter
        self.presenceStore = presenceStore
    }

    private convenience init() {
        self.init(
            realtimeClient: RealtimeClient.shared,
            eventRouter: RealtimeEventRouter.shared,
            presenceStore: .shared
        )
    }

    func activateConversationList(
        _ viewModel: ConversationListViewModel,
        session: SessionStore,
        router: AppRouter
    ) {
        conversationListViewModel = viewModel
        updateContext(session: session, router: router)
        startListeningIfNeeded()
        scheduleConnectAndSyncSubscriptions()
    }

    func deactivateConversationList(_ viewModel: ConversationListViewModel) {
        guard conversationListViewModel === viewModel else { return }
        conversationListViewModel = nil
        scheduleUnsubscribeConversationList()
    }

    func activateChat(
        _ viewModel: ChatViewModel,
        session: SessionStore,
        router: AppRouter
    ) {
        activeChatViewModel = viewModel
        activeConversationID = viewModel.conversation.id
        MessengerDiagnostics.event(
            .activeConversationChanged,
            conversationID: viewModel.conversation.id,
            metadata: ["state": "activated"]
        )
        updateContext(session: session, router: router)
        startListeningIfNeeded()

        Task { [weak self] in
            await self?.subscribeActiveConversationIfNeeded()
        }
    }

    func markActiveConversationReadLocally(conversationID: UUID) {
        guard activeConversationID == conversationID else { return }
        _ = conversationListViewModel?.markConversationReadLocally(conversationID: conversationID)
    }

    var activeChatForDeltaSync: ChatViewModel? {
        activeChatViewModel
    }

    func deactivateChat(_ viewModel: ChatViewModel) {
        guard activeChatViewModel === viewModel else { return }

        viewModel.stopTyping()

        let conversationID = activeConversationID
        activeChatViewModel = nil
        activeConversationID = nil
        subscribedConversationID = nil
        if let conversationID {
            MessengerDiagnostics.event(
                .activeConversationChanged,
                conversationID: conversationID,
                metadata: ["state": "deactivated"]
            )
        }

        guard let conversationID else { return }
        guard !conversationListSubscriptionIDs.contains(conversationID) else {
            NetworkDebug.log("Messenger realtime active unsubscribe skipped; list remains subscribed: \(conversationID)")
            return
        }
        Task { [weak self] in
            await self?.unsubscribe(conversationID: conversationID)
        }
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        activeChatViewModel?.stopTyping()
        activeChatViewModel = nil
        conversationListViewModel = nil
        session = nil
        router = nil
        activeConversationID = nil
        subscribedConversationID = nil
        conversationListSubscriptionIDs = []
        isRefreshingAfterReconnect = false
        conversationFallbackRefreshTask?.cancel()
        conversationFallbackRefreshTask = nil
        activeChatFallbackRefreshTask?.cancel()
        activeChatFallbackRefreshTask = nil
        connectAndSyncGeneration += 1
        presenceStore.clearAll()
    }

    private func updateContext(session: SessionStore, router: AppRouter) {
        self.session = session
        self.router = router
    }

    private func scheduleConnectAndSyncSubscriptions() {
        connectAndSyncGeneration += 1
        let generation = connectAndSyncGeneration

        Task { [weak self] in
            guard let self else { return }
            await self.session?.realtimeClient.connectIfPossible()
            guard generation == self.connectAndSyncGeneration else { return }
            self.syncConversationListSubscriptions()
        }
    }

    private func startListeningIfNeeded() {
        guard eventTask == nil else { return }

        eventTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var iterator = self.eventRouter.stream().makeAsyncIterator()

            while !Task.isCancelled {
                guard let routed = await iterator.next() else { break }
                self.handle(routed.event, context: routed.context)
            }
        }
    }

    private func handle(_ event: RealtimeEvent, context: RealtimeConnectionContext) {
        guard RealtimeTransportGuard.accepts(context, presenceStore: presenceStore) else {
            RealtimeTransportGuard.logIgnoredEvent(event, context: context, presenceStore: presenceStore)
            return
        }

        let ids = diagnosticIDs(for: event)
        MessengerDiagnostics.event(
            .realtimeEventReceived,
            conversationID: ids.conversationID,
            messageID: ids.messageID,
            metadata: [
                "type": event.type,
                "activeConversationID": activeConversationID?.uuidString ?? "none"
            ]
        )

        switch event {
        case .connectionReady:
            Task { [weak self] in
                await self?.reconcileAfterReconnect()
            }

        case .messageCreated(let conversationID, let message):
            handleMessageCreated(message, conversationID: conversationID)

        case .messageEdited(let conversationID, let message):
            handleMessageEdited(message, conversationID: conversationID)

        case .messageDeleted(let conversationID, let payload):
            handleMessageDeleted(payload, conversationID: conversationID)

        case .reactionAdded(let conversationID, let payload):
            handleReactionAdded(payload, conversationID: conversationID)

        case .reactionRemoved(let conversationID, let payload):
            handleReactionRemoved(payload, conversationID: conversationID)

        case .conversationRead(let conversationID, let payload):
            handleConversationRead(payload, conversationID: conversationID)

        case .conversationDelivered(let conversationID, let payload):
            handleConversationDelivered(payload, conversationID: conversationID)

        case .conversationUpdated(_, let payload):
            handleConversationUpdated(payload)

        case .typingStarted(let conversationID, let profileID):
            handleTypingStarted(profileID: profileID, conversationID: conversationID)

        case .typingStopped(let conversationID, let profileID):
            handleTypingStopped(profileID: profileID, conversationID: conversationID)

        case .presenceChanged(let payload):
            handlePresenceChanged(payload, context: context)

        case .pong, .error, .subscriptionReady, .subscriptionRemoved, .unknown:
            break
        }
    }

    private func handleMessageCreated(_ message: MessageDTO, conversationID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            let profileID = await self.currentProfileID()

            await MainActor.run {
                if let profileID {
                    let result = self.applyToActiveConversation(
                        conversationID: conversationID,
                        viaViewModel: { chat in
                            let applied = chat.applyRealtimeMessage(message, currentProfileID: profileID)
                            return applied
                        },
                        viaCache: {
                            MessageCacheStore.shared.applyRealtimeMessage(
                                message,
                                conversationID: conversationID,
                                currentProfileID: profileID
                            )
                        }
                    )
                    MessengerDiagnostics.event(
                        result.applied ? .realtimeEventApplied : .realtimeEventSkipped,
                        conversationID: conversationID,
                        messageID: message.id,
                        metadata: [
                            "type": "message.created",
                            "reason": result.reason,
                            "path": result.path
                        ]
                    )
                    NetworkDebug.log(
                        result.applied
                            ? "Messenger realtime message.created applied (\(result.path))"
                            : "Messenger realtime message.created no-op (\(result.path))"
                    )
                }

                if let profileID {
                    let applied = self.conversationListViewModel?.applyRealtimeMessage(
                        message,
                        currentProfileID: profileID,
                        activeConversationID: self.activeConversationID,
                        router: self.router
                    ) ?? false
                    if !applied {
                        MessengerDiagnostics.event(
                            .realtimeEventFallbackRefresh,
                            conversationID: conversationID,
                            messageID: message.id,
                            metadata: ["type": "message.created", "reason": "conversationMissingFromList"]
                        )
                        self.refreshConversationsFromRealtime()
                    }
                } else {
                    MessengerDiagnostics.event(
                        .realtimeEventFallbackRefresh,
                        conversationID: conversationID,
                        messageID: message.id,
                        metadata: ["type": "message.created", "reason": "missingCurrentProfileID"]
                    )
                    self.refreshConversationsFromRealtime()
                }
            }

            let persisted = await MessengerMessageCacheService.persistRealtimeMessage(
                message,
                eventType: "message.created"
            )
            guard persisted else {
                MessengerDiagnostics.event(
                    .messengerDeliveryAckApplyFailed,
                    conversationID: conversationID,
                    messageID: message.id,
                    metadata: ["source": "realtime", "phase": "persistRealtimeMessage"]
                )
                return
            }

            if let profileID,
               message.senderProfileID != profileID {
                if self.activeConversationID == conversationID {
                    await MainActor.run {
                        self.activeChatViewModel?.acknowledgeVisibleMessages(
                            session: self.session,
                            router: self.router
                        )
                    }
                }
                if let session = self.session, let router = self.router {
                    await MessengerSyncEngine.shared.runGlobalSync(
                        reason: .appForeground,
                        session: session,
                        router: router
                    )
                }
            }
        }
    }

    private func handleMessageEdited(_ message: MessageDTO, conversationID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            let profileID = await self.currentProfileID()

            await MainActor.run {
                if let profileID {
                    let result = self.applyToActiveConversation(
                        conversationID: conversationID,
                        viaViewModel: { chat in
                            chat.applyRealtimeMessage(message, currentProfileID: profileID)
                        },
                        viaCache: {
                            MessageCacheStore.shared.applyRealtimeMessage(
                                message,
                                conversationID: conversationID,
                                currentProfileID: profileID
                            )
                        }
                    )
                    MessengerDiagnostics.event(
                        result.applied ? .realtimeEventApplied : .realtimeEventSkipped,
                        conversationID: conversationID,
                        messageID: message.id,
                        metadata: [
                            "type": "message.edited",
                            "reason": result.reason,
                            "path": result.path
                        ]
                    )
                    NetworkDebug.log(
                        result.applied
                            ? "Messenger realtime message.edited applied (\(result.path))"
                            : "Messenger realtime message.edited no-op (\(result.path))"
                    )
                }

                self.refreshConversationsFromRealtime()
            }

            await MessengerMessageCacheService.persistRealtimeMessage(
                message,
                eventType: "message.edited"
            )
        }
    }

    private func handleMessageDeleted(_ payload: MessageDeletedPayload, conversationID: UUID) {
        let result = applyToActiveConversation(
            conversationID: conversationID,
            viaViewModel: { chat in
                let applied = chat.applyRealtimeDeletedMessage(payload)
                if !applied {
                    MessengerDiagnostics.event(
                        .realtimeEventFallbackRefresh,
                        conversationID: conversationID,
                        messageID: payload.messageID,
                        metadata: ["type": "message.deleted", "reason": "messageMissingInActiveChat"]
                    )
                    refreshActiveChatFromRealtime()
                }
                return applied
            },
            viaCache: {
                MessageCacheStore.shared.markMessageDeleted(
                    conversationID: conversationID,
                    messageID: payload.messageID,
                    deletedAt: payload.deletedAt
                )
            }
        )

        MessengerDiagnostics.event(
            result.applied ? .realtimeEventApplied : .realtimeEventSkipped,
            conversationID: conversationID,
            messageID: payload.messageID,
            metadata: [
                "type": "message.deleted",
                "reason": result.reason,
                "path": result.path
            ]
        )
        NetworkDebug.log(
            result.applied
                ? "Messenger realtime message.deleted applied (\(result.path))"
                : "Messenger realtime message.deleted no-op (\(result.path))"
        )

        refreshConversationsFromRealtime()

        Task {
            await MessengerMessageCacheService.persistMessageDeleted(
                messageID: payload.messageID,
                deletedAt: payload.deletedAt
            )
        }
    }

    private func handleReactionAdded(_ payload: ReactionAddedPayload, conversationID: UUID) {
        let result = applyToActiveConversation(
            conversationID: conversationID,
            viaViewModel: { chat in
                let applied = chat.applyRealtimeReactionAdded(payload)
                if !applied, !chat.messages.contains(where: { $0.id == payload.messageID }) {
                    refreshActiveChatFromRealtime()
                }
                return applied
            },
            viaCache: {
                MessageCacheStore.shared.applyRealtimeReactionAdded(payload, conversationID: conversationID)
            }
        )
        MessengerDiagnostics.event(
            result.applied ? .realtimeEventApplied : .realtimeEventSkipped,
            conversationID: conversationID,
            messageID: payload.messageID,
            metadata: [
                "type": "reaction.added",
                "reason": result.reason,
                "path": result.path
            ]
        )
        NetworkDebug.log(
            result.applied
                ? "Messenger realtime reaction.added applied (\(result.path))"
                : "Messenger realtime reaction.added no-op (\(result.path))"
        )
    }

    private func handleReactionRemoved(_ payload: ReactionRemovedPayload, conversationID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            let profileID = await self.currentProfileID()

            await MainActor.run {
                let result = self.applyToActiveConversation(
                    conversationID: conversationID,
                    viaViewModel: { chat in
                        let applied = chat.applyRealtimeReactionRemoved(
                            payload,
                            currentProfileID: profileID
                        )
                        if !applied, !chat.messages.contains(where: { $0.id == payload.messageID }) {
                            self.refreshActiveChatFromRealtime()
                        }
                        return applied
                    },
                    viaCache: {
                        MessageCacheStore.shared.applyRealtimeReactionRemoved(
                            payload,
                            conversationID: conversationID,
                            currentProfileID: profileID
                        )
                    }
                )
                MessengerDiagnostics.event(
                    result.applied ? .realtimeEventApplied : .realtimeEventSkipped,
                    conversationID: conversationID,
                    messageID: payload.messageID,
                    metadata: [
                        "type": "reaction.removed",
                        "reason": result.reason,
                        "path": result.path
                    ]
                )
                NetworkDebug.log(
                    result.applied
                        ? "Messenger realtime reaction.removed applied (\(result.path))"
                        : "Messenger realtime reaction.removed no-op (\(result.path))"
                )
            }
        }
    }

    private func handleConversationRead(_ payload: ConversationReadPayload, conversationID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            let profileID = await self.currentProfileID()

            await MainActor.run {
                _ = self.conversationListViewModel?.applyRealtimeConversationRead(
                    conversationID: conversationID,
                    profileID: payload.profileID,
                    currentProfileID: profileID
                )

                guard payload.profileID != profileID else { return }
                let result = self.applyToActiveConversation(
                    conversationID: conversationID,
                    viaViewModel: { chat in
                        chat.applyDeliveryStatus(
                            .read,
                            messageID: payload.messageID,
                            cutoffDate: payload.lastReadAt
                        )
                    },
                    viaCache: {
                        MessageCacheStore.shared.applyDeliveryStatus(
                            conversationID: conversationID,
                            status: .read,
                            messageID: payload.messageID,
                            cutoffDate: payload.lastReadAt
                        )
                    }
                )
                NetworkDebug.log(
                    result.applied
                        ? "Messenger realtime conversation.read applied (\(result.path))"
                        : "Messenger realtime conversation.read ignored (\(result.path))"
                )
            }
        }
    }

    private func handleConversationDelivered(_ payload: ConversationDeliveredPayload, conversationID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            let profileID = await self.currentProfileID()

            await MainActor.run {
                guard payload.profileID != profileID else { return }
                let result = self.applyToActiveConversation(
                    conversationID: conversationID,
                    viaViewModel: { chat in
                        chat.applyDeliveryStatus(
                            .delivered,
                            messageID: payload.messageID,
                            cutoffDate: payload.lastDeliveredAt
                        )
                    },
                    viaCache: {
                        MessageCacheStore.shared.applyDeliveryStatus(
                            conversationID: conversationID,
                            status: .delivered,
                            messageID: payload.messageID,
                            cutoffDate: payload.lastDeliveredAt
                        )
                    }
                )
                NetworkDebug.log(
                    result.applied
                        ? "Messenger realtime conversation.delivered applied (\(result.path))"
                        : "Messenger realtime conversation.delivered ignored (\(result.path))"
                )
            }
        }
    }

    private func handleConversationUpdated(_ payload: ConversationUpdatedPayload) {
        let applied = conversationListViewModel?.applyRealtimeConversationUpdated(payload) ?? false
        if !applied {
            MessengerDiagnostics.event(
                .realtimeEventFallbackRefresh,
                conversationID: payload.conversationID,
                metadata: ["type": "conversation.updated", "reason": "conversationMissingFromList"]
            )
            refreshConversationsFromRealtime()
        } else {
            MessengerDiagnostics.event(
                .realtimeEventApplied,
                conversationID: payload.conversationID,
                metadata: ["type": "conversation.updated", "reason": "conversationList"]
            )
        }
    }

    private func handleTypingStarted(profileID: UUID, conversationID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            let currentProfileID = await self.currentProfileID()
            await MainActor.run {
                if let currentProfileID, profileID == currentProfileID { return }
                let previousOnline = self.presenceStore.isOnline(profileID: profileID)
                let applied = self.presenceStore.applyTypingOnlineHint(profileID: profileID)
                MessengerDiagnostics.event(
                    .presenceStateApplied,
                    conversationID: conversationID,
                    metadata: [
                        "source": "typingHint",
                        "incomingOnline": "true",
                        "previousOnline": "\(previousOnline)",
                        "applied": "\(applied)",
                        "profileID": MessengerDiagnostics.sanitizeID(profileID)
                    ]
                )
                guard self.activeConversationID == conversationID else { return }
                self.activeChatViewModel?.applyTypingStarted(profileID: profileID)
            }
        }
    }

    private func handleTypingStopped(profileID: UUID, conversationID: UUID) {
        Task { [weak self] in
            await MainActor.run {
                self?.presenceStore.clearTypingHint(profileID: profileID)
                guard self?.activeConversationID == conversationID else { return }
                self?.activeChatViewModel?.applyTypingStopped(profileID: profileID)
            }
        }
    }

    private func handlePresenceChanged(_ payload: PresenceChangedPayload, context: RealtimeConnectionContext) {
        Task { [weak self] in
            guard let self else { return }
            let currentProfileID = await self.currentProfileID()
            await MainActor.run {
                guard RealtimeTransportGuard.accepts(context, presenceStore: self.presenceStore) else {
                    RealtimeTransportGuard.logIgnoredEvent(
                        .presenceChanged(payload: payload),
                        context: context,
                        presenceStore: self.presenceStore
                    )
                    return
                }
                MessengerDiagnostics.event(
                    .presenceEventReceived,
                    metadata: [
                        "source": "realtime",
                        "incomingOnline": "\(payload.isOnline)",
                        "profileID": MessengerDiagnostics.sanitizeID(payload.profileID)
                    ]
                )
                if let currentProfileID, payload.profileID == currentProfileID {
                    MessengerDiagnostics.event(
                        .presenceStateIgnored,
                        metadata: [
                            "source": "realtime",
                            "reason": "selfEvent",
                            "profileID": MessengerDiagnostics.sanitizeID(payload.profileID)
                        ]
                    )
                    return
                }
                let previousOnline = self.presenceStore.isOnline(profileID: payload.profileID)
                let applied = self.presenceStore.apply(
                    payload,
                    connectionEpoch: context.connectionEpoch,
                    sessionGeneration: context.sessionGeneration
                )
                MessengerDiagnostics.event(
                    applied ? .presenceStateApplied : .presenceStateIgnored,
                    metadata: [
                        "source": "realtime",
                        "incomingOnline": "\(payload.isOnline)",
                        "previousOnline": "\(previousOnline)",
                        "profileID": MessengerDiagnostics.sanitizeID(payload.profileID)
                    ]
                )
            }
        }
    }

    private func reconcileAfterReconnect() async {
        guard !isRefreshingAfterReconnect else { return }
        isRefreshingAfterReconnect = true
        NetworkDebug.log("Messenger realtime reconnect reconcile started")

        resetTrackedSubscriptions()
        // Connection epoch advanced when the new socket was created; preserve provisional online only.
        presenceStore.markAllPreservedAcrossReconnect()

        if let session, let router {
            await MessengerSyncEngine.shared.runGlobalSync(
                reason: .realtimeReconnect,
                session: session,
                router: router
            )
        } else {
            await refreshConversations()
            await refreshActiveChat()
        }

        activeChatViewModel?.clearTypingState()
        await subscribeActiveConversationIfNeeded(force: true)

        isRefreshingAfterReconnect = false
        NetworkDebug.log("Messenger realtime reconnect reconcile completed")
    }

    private func resetTrackedSubscriptions() {
        conversationListSubscriptionIDs.removeAll()
        subscribedConversationID = nil
        NetworkDebug.log("Messenger realtime tracked subscriptions reset")
    }

    private func refreshConversationsFromRealtime() {
        MessengerDiagnostics.event(
            .realtimeEventFallbackRefresh,
            metadata: ["target": "conversationList"]
        )
        guard conversationFallbackRefreshTask == nil else { return }
        conversationFallbackRefreshTask = Task { @MainActor [weak self] in
            defer { self?.conversationFallbackRefreshTask = nil }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.refreshConversations()
        }
    }

    private func refreshActiveChatFromRealtime() {
        MessengerDiagnostics.event(
            .realtimeEventFallbackRefresh,
            conversationID: activeConversationID,
            metadata: ["target": "activeChat"]
        )
        guard activeChatFallbackRefreshTask == nil else { return }
        activeChatFallbackRefreshTask = Task { @MainActor [weak self] in
            defer { self?.activeChatFallbackRefreshTask = nil }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.refreshActiveChat()
        }
    }

    private func refreshConversations() async {
        guard let session, let router, let conversationListViewModel else { return }
        await conversationListViewModel.refreshFromRealtime(session: session, router: router)
        syncConversationListSubscriptions()
    }

    private func refreshActiveChat() async {
        guard let session, let router, let activeChatViewModel else { return }
        await activeChatViewModel.refreshFromRealtime(session: session, router: router)
    }

    private func subscribeActiveConversationIfNeeded(force: Bool = false) async {
        guard let conversationID = activeConversationID else { return }
        guard force || subscribedConversationID != conversationID else { return }

        do {
            try await realtimeClient.subscribe(conversationID: conversationID)
            subscribedConversationID = conversationID
            NetworkDebug.log("Messenger realtime active conversation subscribed: \(conversationID)")
        } catch {
            NetworkDebug.logError(error, prefix: "Messenger realtime subscribe failed")
        }
    }

    private func syncConversationListSubscriptions(force: Bool = false) {
        guard let conversationListViewModel else { return }

        if force {
            resetTrackedSubscriptions()
        }

        let visibleConversationIDs = Set(conversationListViewModel.conversations.map(\.id))
        let idsToSubscribe = visibleConversationIDs.subtracting(conversationListSubscriptionIDs)
        let idsToUnsubscribe = conversationListSubscriptionIDs.subtracting(visibleConversationIDs)

        guard !idsToSubscribe.isEmpty || !idsToUnsubscribe.isEmpty else { return }

        Task { [weak self] in
            await self?.session?.realtimeClient.connectIfPossible()
            await self?.subscribeConversationList(idsToSubscribe)
            await self?.unsubscribeConversationList(idsToUnsubscribe)
        }
    }

    private func subscribeConversationList(_ conversationIDs: Set<UUID>) async {
        for conversationID in conversationIDs {
            do {
                try await realtimeClient.subscribe(conversationID: conversationID)
                conversationListSubscriptionIDs.insert(conversationID)
                NetworkDebug.log("Messenger realtime list conversation subscribed: \(conversationID)")
            } catch {
                NetworkDebug.logError(error, prefix: "Messenger realtime list subscribe failed")
            }
        }
    }

    private func scheduleUnsubscribeConversationList(_ conversationIDs: Set<UUID>? = nil) {
        let ids = conversationIDs ?? conversationListSubscriptionIDs
        guard !ids.isEmpty else { return }

        Task { [weak self] in
            await self?.unsubscribeConversationList(ids)
        }
    }

    private func unsubscribeConversationList(_ conversationIDs: Set<UUID>) async {
        for conversationID in conversationIDs {
            guard activeConversationID != conversationID else {
                conversationListSubscriptionIDs.remove(conversationID)
                NetworkDebug.log("Messenger realtime list unsubscribe skipped; active chat remains subscribed: \(conversationID)")
                continue
            }

            do {
                try await realtimeClient.unsubscribe(conversationID: conversationID)
                conversationListSubscriptionIDs.remove(conversationID)
                NetworkDebug.log("Messenger realtime list conversation unsubscribed: \(conversationID)")
            } catch {
                NetworkDebug.logError(error, prefix: "Messenger realtime list unsubscribe failed")
            }
        }
    }

    private func unsubscribe(conversationID: UUID) async {
        do {
            try await realtimeClient.unsubscribe(conversationID: conversationID)
            NetworkDebug.log("Messenger realtime active conversation unsubscribed: \(conversationID)")
        } catch {
            NetworkDebug.logError(error, prefix: "Messenger realtime unsubscribe failed")
        }
    }

    private func currentProfileID() async -> UUID? {
        guard let session else { return nil }

        if let profileID = session.currentProfile?.id {
            return profileID
        }

        return try? await MessengerSessionSupport.resolveCurrentProfileID(session: session)
    }

    private struct ActiveConversationApplyResult {
        let applied: Bool
        let path: String

        static let activeChatPath = "activeChatViewModel"
        static let nilViewModelFallbackPath = "activeChatViewModelNilFallback"
        static let inactiveCachePath = "cachedInactiveConversation"

        var reason: String {
            switch path {
            case Self.activeChatPath:
                return applied ? "activeChatApplied" : "activeChatNoOp"
            case Self.nilViewModelFallbackPath:
                return applied ? "activeChatViewModelNilFallback" : "activeChatViewModelNilFallbackNoOp"
            default:
                return applied ? "cachedInactiveConversation" : "cachedInactiveConversationNoOp"
            }
        }
    }

    private func applyToActiveConversation(
        conversationID: UUID,
        viaViewModel: (ChatViewModel) -> Bool,
        viaCache: () -> Bool
    ) -> ActiveConversationApplyResult {
        guard activeConversationID == conversationID else {
            let applied = viaCache()
            return ActiveConversationApplyResult(
                applied: applied,
                path: ActiveConversationApplyResult.inactiveCachePath
            )
        }

        if let chat = activeChatViewModel {
            let applied = viaViewModel(chat)
            return ActiveConversationApplyResult(
                applied: applied,
                path: ActiveConversationApplyResult.activeChatPath
            )
        }

        let applied = viaCache()
        MessengerDiagnostics.event(
            .realtimeActiveChatViewModelNilFallback,
            conversationID: conversationID,
            metadata: [
                "applied": applied ? "true" : "false",
                "path": ActiveConversationApplyResult.nilViewModelFallbackPath
            ]
        )
        return ActiveConversationApplyResult(
            applied: applied,
            path: ActiveConversationApplyResult.nilViewModelFallbackPath
        )
    }

    #if DEBUG
    /// Simulates active conversation tracking after the weak chat view model was released.
    func testing_simulateActiveConversationWithoutViewModel(conversationID: UUID) {
        activeConversationID = conversationID
        activeChatViewModel = nil
    }
    #endif

    private func diagnosticIDs(for event: RealtimeEvent) -> (conversationID: UUID?, messageID: UUID?) {
        switch event {
        case .messageCreated(let conversationID, let message),
             .messageEdited(let conversationID, let message):
            return (conversationID, message.id)
        case .messageDeleted(let conversationID, let payload):
            return (conversationID, payload.messageID)
        case .reactionAdded(let conversationID, let payload):
            return (conversationID, payload.messageID)
        case .reactionRemoved(let conversationID, let payload):
            return (conversationID, payload.messageID)
        case .conversationRead(let conversationID, let payload):
            return (conversationID, payload.messageID)
        case .conversationDelivered(let conversationID, let payload):
            return (conversationID, payload.messageID)
        case .conversationUpdated(let conversationID, _),
             .typingStarted(let conversationID, _),
             .typingStopped(let conversationID, _),
             .subscriptionReady(let conversationID),
             .subscriptionRemoved(let conversationID):
            return (conversationID, nil)
        case .connectionReady, .pong, .error, .presenceChanged, .unknown:
            return (nil, nil)
        }
    }
}
