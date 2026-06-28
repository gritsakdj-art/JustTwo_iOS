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
    private var eventTask: Task<Void, Never>?
    private var activeConversationID: UUID?
    private var subscribedConversationID: UUID?
    private var conversationListSubscriptionIDs: Set<UUID> = []
    private var isRefreshingAfterReconnect = false

    init(
        realtimeClient: RealtimeClient = .shared,
        eventRouter: RealtimeEventRouter = .shared
    ) {
        self.realtimeClient = realtimeClient
        self.eventRouter = eventRouter
    }

    func activateConversationList(
        _ viewModel: ConversationListViewModel,
        session: SessionStore,
        router: AppRouter
    ) {
        conversationListViewModel = viewModel
        updateContext(session: session, router: router)
        startListeningIfNeeded()
        syncConversationListSubscriptions()
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
        updateContext(session: session, router: router)
        startListeningIfNeeded()

        Task { [weak self] in
            await self?.subscribeActiveConversationIfNeeded()
        }
    }

    func deactivateChat(_ viewModel: ChatViewModel) {
        guard activeChatViewModel === viewModel else { return }

        let conversationID = activeConversationID
        activeChatViewModel = nil
        activeConversationID = nil
        subscribedConversationID = nil

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
        activeChatViewModel = nil
        conversationListViewModel = nil
        session = nil
        router = nil
        activeConversationID = nil
        subscribedConversationID = nil
        conversationListSubscriptionIDs = []
        isRefreshingAfterReconnect = false
    }

    private func updateContext(session: SessionStore, router: AppRouter) {
        self.session = session
        self.router = router
    }

    private func startListeningIfNeeded() {
        guard eventTask == nil else { return }

        eventTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var iterator = self.eventRouter.stream().makeAsyncIterator()

            while !Task.isCancelled {
                guard let event = await iterator.next() else { break }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: RealtimeEvent) {
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

        case .conversationUpdated(_, let payload):
            handleConversationUpdated(payload)

        case .pong, .error, .subscriptionReady, .subscriptionRemoved, .unknown:
            break
        }
    }

    private func handleMessageCreated(_ message: MessageDTO, conversationID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            let profileID = await self.currentProfileID()

            await MainActor.run {
                if self.activeConversationID == conversationID, let profileID {
                    let inserted = self.activeChatViewModel?.applyRealtimeMessage(
                        message,
                        currentProfileID: profileID
                    ) ?? false
                    NetworkDebug.log(inserted ? "Messenger realtime message.created applied" : "Messenger realtime duplicate/updated message.created handled")
                }

                if let profileID {
                    let applied = self.conversationListViewModel?.applyRealtimeMessage(
                        message,
                        currentProfileID: profileID,
                        activeConversationID: self.activeConversationID
                    ) ?? false
                    if !applied {
                        self.refreshConversationsFromRealtime()
                    }
                } else {
                    self.refreshConversationsFromRealtime()
                }
            }
        }
    }

    private func handleMessageEdited(_ message: MessageDTO, conversationID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            let profileID = await self.currentProfileID()

            await MainActor.run {
                if self.activeConversationID == conversationID, let profileID {
                    _ = self.activeChatViewModel?.applyRealtimeMessage(message, currentProfileID: profileID)
                    NetworkDebug.log("Messenger realtime message.edited applied")
                }

                self.refreshConversationsFromRealtime()
            }
        }
    }

    private func handleMessageDeleted(_ payload: MessageDeletedPayload, conversationID: UUID) {
        if activeConversationID == conversationID {
            let applied = activeChatViewModel?.applyRealtimeDeletedMessage(payload) ?? false
            if !applied {
                refreshActiveChatFromRealtime()
            }
            NetworkDebug.log("Messenger realtime message.deleted applied")
        }

        refreshConversationsFromRealtime()
    }

    private func handleReactionAdded(_ payload: ReactionAddedPayload, conversationID: UUID) {
        guard activeConversationID == conversationID else { return }

        let applied = activeChatViewModel?.applyRealtimeReactionAdded(payload) ?? false
        if !applied {
            refreshActiveChatFromRealtime()
        }
        NetworkDebug.log("Messenger realtime reaction.added applied")
    }

    private func handleReactionRemoved(_ payload: ReactionRemovedPayload, conversationID: UUID) {
        guard activeConversationID == conversationID else { return }

        Task { [weak self] in
            guard let self else { return }
            let profileID = await self.currentProfileID()

            await MainActor.run {
                let applied = self.activeChatViewModel?.applyRealtimeReactionRemoved(
                    payload,
                    currentProfileID: profileID
                ) ?? false
                if !applied {
                    self.refreshActiveChatFromRealtime()
                }
                NetworkDebug.log("Messenger realtime reaction.removed applied")
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
            }
        }
    }

    private func handleConversationUpdated(_ payload: ConversationUpdatedPayload) {
        let applied = conversationListViewModel?.applyRealtimeConversationUpdated(payload) ?? false
        if !applied {
            refreshConversationsFromRealtime()
        }
    }

    private func reconcileAfterReconnect() async {
        guard !isRefreshingAfterReconnect else { return }
        isRefreshingAfterReconnect = true
        NetworkDebug.log("Messenger realtime reconnect reconcile started")

        await refreshConversations()
        await refreshActiveChat()
        await subscribeActiveConversationIfNeeded(force: true)

        isRefreshingAfterReconnect = false
        NetworkDebug.log("Messenger realtime reconnect reconcile completed")
    }

    private func refreshConversationsFromRealtime() {
        Task { [weak self] in
            await self?.refreshConversations()
        }
    }

    private func refreshActiveChatFromRealtime() {
        Task { [weak self] in
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

    private func syncConversationListSubscriptions() {
        guard let conversationListViewModel else { return }

        let visibleConversationIDs = Set(conversationListViewModel.conversations.map(\.id))
        let idsToSubscribe = visibleConversationIDs.subtracting(conversationListSubscriptionIDs)
        let idsToUnsubscribe = conversationListSubscriptionIDs.subtracting(visibleConversationIDs)

        guard !idsToSubscribe.isEmpty || !idsToUnsubscribe.isEmpty else { return }

        Task { [weak self] in
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
}
