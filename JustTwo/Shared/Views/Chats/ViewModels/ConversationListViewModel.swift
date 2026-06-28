import Foundation

@MainActor
@Observable
final class ConversationListViewModel {

    private(set) var conversations: [ChatConversationPreview] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private var didLoad = false
    private var appliedRealtimeMessageIDs: Set<UUID> = []

    static func preview(
        conversations: [ChatConversationPreview] = ChatUIMockData.conversations,
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
            didLoad = true
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
    func applyRealtimeMessage(
        _ dto: MessageDTO,
        currentProfileID: UUID,
        activeConversationID: UUID?
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
}
