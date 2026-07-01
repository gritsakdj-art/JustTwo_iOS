import Foundation

@MainActor
@Observable
final class ConversationListViewModel {

    static let shared = ConversationListViewModel()

    private(set) var conversations: [ChatConversationPreview] = []
    private(set) var isLoading = false
    var errorMessage: String?

    var totalUnreadCount: Int {
        conversations.reduce(0) { $0 + $1.unreadCount }
    }
    private var didLoad = false
    private var refreshTask: Task<Void, Never>?
    private var appliedRealtimeMessageIDs: Set<UUID> = []

    func reset() {
        refreshTask?.cancel()
        refreshTask = nil
        conversations = []
        isLoading = false
        errorMessage = nil
        didLoad = false
        appliedRealtimeMessageIDs = []
        syncMessengerBadge()
    }

    static func preview(
        conversations: [ChatConversationPreview],
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) -> ConversationListViewModel {
        let viewModel = ConversationListViewModel()
        viewModel.conversations = conversations
        viewModel.isLoading = isLoading
        viewModel.errorMessage = errorMessage
        viewModel.didLoad = true
        return viewModel
    }

    static func preview(
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) -> ConversationListViewModel {
        preview(
            conversations: ChatUIMockData.conversations,
            isLoading: isLoading,
            errorMessage: errorMessage
        )
    }

    func loadIfNeeded(session: SessionStore, router: AppRouter) async {
        guard !didLoad else { return }
        await refresh(session: session, router: router)
    }

    func activateRealtime(session: SessionStore, router: AppRouter) {
        MessengerRealtimeCoordinator.shared.activateConversationList(self, session: session, router: router)
    }

    func deactivateRealtime() {
        MessengerRealtimeCoordinator.shared.deactivateConversationList(self)
    }

    func refresh(session: SessionStore, router: AppRouter) async {
        if let refreshTask {
            await refreshTask.value
            return
        }

        let task = Task { @MainActor in
            await performRefresh(session: session, router: router)
        }
        refreshTask = task
        await task.value
        if refreshTask == task {
            refreshTask = nil
        }
    }

    private func performRefresh(session: SessionStore, router: AppRouter) async {
        let showLoading = conversations.isEmpty
        if showLoading {
            isLoading = true
        }
        errorMessage = nil

        do {
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            let response = try await ConversationService.fetchConversations()
            conversations = response.conversations.map {
                ChatUIMapping.conversationPreview(from: $0, currentProfileID: profileID)
            }
            await ConversationDeliveryAckCoordinator.shared.acknowledgeDeliveredForConversations(
                response.conversations,
                currentProfileID: profileID,
                session: session,
                router: router
            )
            syncMessengerBadge()
            didLoad = true
            ConversationAvatarsStartupLoader.shared.preloadRemainingIfNeeded(for: conversations)
        } catch let error as NetworkError {
            if let message = MessengerSessionSupport.handleNetworkError(error, session: session, router: router) {
                errorMessage = message
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refreshFromRealtime(session: SessionStore, router: AppRouter) async {
        NetworkDebug.log("Messenger realtime conversations refresh started")
        await refresh(session: session, router: router)
        NetworkDebug.log("Messenger realtime conversations refresh completed")
    }

    @discardableResult
    func applyOptimisticOutgoing(
        conversationID: UUID,
        previewText: String,
        sentAt: Date
    ) -> Bool {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return false
        }

        let current = conversations[index]
        let updated = current.replacingActivity(
            lastMessageText: previewText,
            lastSenderName: String(localized: "chats.you"),
            lastMessageAt: sentAt
        )

        conversations.remove(at: index)
        conversations.insert(updated, at: 0)
        sortConversations()
        return true
    }

    @discardableResult
    func applyOutgoingConfirmed(
        conversationID: UUID,
        message: MessageDTO,
        currentProfileID: UUID
    ) -> Bool {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return false
        }

        let current = conversations[index]
        let updated = current.replacingActivity(
            lastMessageText: ChatUIMapping.realtimeLastMessageText(from: message),
            lastSenderName: ChatUIMapping.realtimeLastSenderName(
                from: message,
                currentProfileID: currentProfileID,
                fallbackOtherName: current.title
            ),
            lastMessageAt: message.createdAt ?? current.lastMessageAt
        )

        conversations.remove(at: index)
        conversations.insert(updated, at: 0)
        sortConversations()
        return true
    }

    @discardableResult
    func applyRealtimeMessage(
        _ dto: MessageDTO,
        currentProfileID: UUID,
        activeConversationID: UUID?,
        router: AppRouter? = nil
    ) -> Bool {
        guard let index = conversations.firstIndex(where: { $0.id == dto.conversationID }) else {
            return false
        }

        let current = conversations[index]
        let isMine = dto.senderProfileID == currentProfileID
        let isNewRealtimeMessage = appliedRealtimeMessageIDs.insert(dto.id).inserted
        let shouldIncrementUnread = isNewRealtimeMessage && activeConversationID != dto.conversationID && !isMine
        let updated = current.replacingActivity(
            lastMessageText: ChatUIMapping.realtimeLastMessageText(from: dto),
            lastSenderName: ChatUIMapping.realtimeLastSenderName(
                from: dto,
                currentProfileID: currentProfileID,
                fallbackOtherName: current.title
            ),
            lastMessageAt: dto.createdAt ?? current.lastMessageAt,
            unreadCount: shouldIncrementUnread ? current.unreadCount + 1 : current.unreadCount
        )

        conversations.remove(at: index)
        conversations.insert(updated, at: 0)
        sortConversations()
        syncMessengerBadge()

        if shouldIncrementUnread {
            let selectedTab = router?.selectedMainTab ?? AppRouter.shared.selectedMainTab
            if MessengerNotificationService.shouldPresentIncomingMessage(
                conversationID: dto.conversationID,
                senderProfileID: dto.senderProfileID,
                currentProfileID: currentProfileID,
                activeConversationID: activeConversationID,
                selectedTab: selectedTab
            ) {
                MessengerNotificationService.shared.presentIncomingMessage(
                    conversationID: dto.conversationID,
                    messageID: dto.id,
                    partnerName: current.title,
                    previewText: ChatUIMapping.realtimeLastMessageText(from: dto),
                    avatarPhotoID: current.avatarPhotoID
                )
            }
        }

        return true
    }

    @discardableResult
    func applyRealtimeConversationRead(
        conversationID: UUID,
        profileID: UUID,
        currentProfileID: UUID?
    ) -> Bool {
        guard profileID == currentProfileID,
              let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return false
        }

        conversations[index] = conversations[index].replacingActivity(unreadCount: 0)
        syncMessengerBadge()
        return true
    }

    @discardableResult
    func markConversationReadLocally(conversationID: UUID) -> Bool {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return false
        }

        guard conversations[index].unreadCount > 0 else {
            return true
        }

        conversations[index] = conversations[index].replacingActivity(unreadCount: 0)
        syncMessengerBadge()
        return true
    }

    @discardableResult
    func applyRealtimeConversationUpdated(_ payload: ConversationUpdatedPayload) -> Bool {
        guard let index = conversations.firstIndex(where: { $0.id == payload.conversationID }) else {
            return false
        }

        conversations[index] = conversations[index].replacingActivity(
            lastMessageAt: payload.lastMessageAt ?? payload.updatedAt
        )
        sortConversations()
        return true
    }

    private func sortConversations() {
        conversations.sort {
            ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast)
        }
    }

    private func syncMessengerBadge() {
        MessengerBadgeStore.shared.setUnreadCount(totalUnreadCount)
    }
}
