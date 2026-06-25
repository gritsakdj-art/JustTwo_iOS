import Foundation

@MainActor
@Observable
final class ConversationListViewModel {

    private(set) var conversations: [ChatConversationPreview] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private var didLoad = false

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
}
