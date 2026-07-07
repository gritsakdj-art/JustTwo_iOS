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
    private var refreshGeneration = 0
    private var listContentGeneration = 0
    private var appliedRealtimeMessageIDs: Set<UUID> = []

    func reset() {
        refreshTask?.cancel()
        refreshTask = nil
        conversations = []
        isLoading = false
        errorMessage = nil
        didLoad = false
        appliedRealtimeMessageIDs = []
        refreshGeneration += 1
        listContentGeneration += 1
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
        refreshGeneration += 1
        let generation = refreshGeneration

        let showLoading = conversations.isEmpty
        if showLoading {
            isLoading = true
        }
        errorMessage = nil

        do {
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            let contentGenerationAtStart = listContentGeneration
            let cached = await MessengerConversationCacheService.hydrateCachedPreviews(
                currentProfileID: profileID
            )

            if let cached,
               !cached.isEmpty,
               generation == refreshGeneration,
               contentGenerationAtStart == listContentGeneration {
                conversations = cached
                syncMessengerBadge()
                if showLoading {
                    isLoading = false
                }
                MessengerDiagnostics.event(
                    .messengerConversationCacheHydratedUI,
                    metadata: ["count": "\(cached.count)"]
                )
            } else if let cached,
                      !cached.isEmpty,
                      generation == refreshGeneration,
                      contentGenerationAtStart != listContentGeneration {
                MessengerDiagnostics.event(
                    .messengerConversationCacheSkippedStale,
                    metadata: ["source": "cache"]
                )
            }

            let networkStartedAt = Date()
            MessengerDiagnostics.event(.messengerConversationCacheNetworkRefreshStarted)

            let response = try await ConversationService.fetchConversations()

            guard generation == refreshGeneration else {
                MessengerDiagnostics.event(
                    .messengerConversationCacheSkippedStale,
                    metadata: ["source": "rest"]
                )
                return
            }

            let restPreviews = response.conversations.map {
                ChatUIMapping.conversationPreview(from: $0, currentProfileID: profileID)
            }
            conversations = mergeRESTPreviews(restPreviews, with: conversations)
            bumpListContentGeneration()
            await ConversationDeliveryAckCoordinator.shared.acknowledgeDeliveredForConversations(
                response.conversations,
                currentProfileID: profileID,
                session: session,
                router: router
            )
            await MessengerConversationCacheService.persistRESTConversations(response.conversations)
            syncMessengerBadge()
            didLoad = true
            ConversationAvatarsStartupLoader.shared.preloadRemainingIfNeeded(for: conversations)

            MessengerDiagnostics.event(
                .messengerConversationCacheNetworkRefreshSucceeded,
                metadata: [
                    "count": "\(response.conversations.count)",
                    "durationMs": "\(durationMilliseconds(since: networkStartedAt))"
                ]
            )
        } catch let error as NetworkError {
            guard generation == refreshGeneration else { return }

            if conversations.isEmpty,
               let message = MessengerSessionSupport.handleNetworkError(error, session: session, router: router) {
                errorMessage = message
            } else if conversations.isEmpty {
                errorMessage = error.localizedDescription
            } else if let message = MessengerSessionSupport.handleNetworkError(error, session: session, router: router) {
                errorMessage = message
            }

            MessengerDiagnostics.event(
                .messengerConversationCacheNetworkRefreshFailed,
                metadata: [
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "cachedCount": "\(conversations.count)"
                ]
            )
        } catch {
            guard generation == refreshGeneration else { return }

            if conversations.isEmpty {
                errorMessage = error.localizedDescription
            }

            MessengerDiagnostics.event(
                .messengerConversationCacheNetworkRefreshFailed,
                metadata: [
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "cachedCount": "\(conversations.count)"
                ]
            )
        }

        isLoading = false
    }

    private func durationMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
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
        bumpListContentGeneration()
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
        Task {
            await MessengerConversationCacheService.persistRealtimeMessage(
                message,
                unreadCount: updated.unreadCount
            )
        }
        bumpListContentGeneration()
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

        Task {
            await MessengerConversationCacheService.persistRealtimeMessage(
                dto,
                unreadCount: updated.unreadCount
            )
        }

        bumpListContentGeneration()
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
        Task {
            await MessengerConversationCacheService.persistRealtimeConversationRead(conversationID: conversationID)
        }
        bumpListContentGeneration()
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
        Task {
            await MessengerConversationCacheService.persistRealtimeConversationRead(conversationID: conversationID)
        }
        bumpListContentGeneration()
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
        Task {
            await MessengerConversationCacheService.persistRealtimeConversationUpdated(
                conversationID: payload.conversationID,
                lastMessageAt: payload.lastMessageAt ?? payload.updatedAt
            )
        }
        bumpListContentGeneration()
        return true
    }

    @discardableResult
    func applyDeltaConversation(
        _ dto: ConversationDTO,
        currentProfileID: UUID,
        activeConversationID: UUID?
    ) -> Bool {
        let incoming = ChatUIMapping.conversationPreview(from: dto, currentProfileID: currentProfileID)
        let merged: ChatConversationPreview
        if activeConversationID == dto.id {
            merged = incoming.replacingActivity(unreadCount: 0)
        } else if let index = conversations.firstIndex(where: { $0.id == dto.id }) {
            let existing = conversations[index]
            let unreadCount = max(existing.unreadCount, incoming.unreadCount)
            merged = incoming.replacingActivity(unreadCount: unreadCount)
        } else {
            merged = incoming
        }

        if let index = conversations.firstIndex(where: { $0.id == dto.id }) {
            conversations[index] = merged
        } else {
            conversations.insert(merged, at: 0)
        }
        sortConversations()
        syncMessengerBadge()
        bumpListContentGeneration()
        return true
    }

    private func mergeRESTPreviews(
        _ restPreviews: [ChatConversationPreview],
        with existing: [ChatConversationPreview]
    ) -> [ChatConversationPreview] {
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        return restPreviews.map { restPreview in
            guard let existingPreview = existingByID[restPreview.id] else {
                return restPreview
            }

            let existingAt = existingPreview.lastMessageAt ?? .distantPast
            let restAt = restPreview.lastMessageAt ?? .distantPast
            let unreadCount = max(existingPreview.unreadCount, restPreview.unreadCount)

            guard existingAt > restAt else {
                return restPreview.replacingActivity(unreadCount: unreadCount)
            }

            return restPreview.replacingActivity(
                lastMessageText: existingPreview.lastMessageText,
                lastSenderName: existingPreview.lastSenderName,
                lastMessageAt: existingPreview.lastMessageAt,
                unreadCount: unreadCount
            )
        }
    }

    private func bumpListContentGeneration() {
        listContentGeneration += 1
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
