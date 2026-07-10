import Foundation
import Testing
@testable import JustTwo

@MainActor
struct PushNotificationRoutingCoordinatorTests {

    private let conversationID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let firstMessageID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let secondMessageID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    @Test
    func keepsPendingRouteWhenConversationIsMissing() async {
        let coordinator = PushNotificationRoutingCoordinator.shared
        let router = AppRouter.shared
        let session = SessionStore.shared

        coordinator.clearPendingRoute()
        coordinator.testingSkipConversationRefresh = true
        coordinator.testingBypassApplyGuards = true
        coordinator.testingConversationListViewModel = ConversationListViewModel.preview(conversations: [])
        defer {
            coordinator.testingSkipConversationRefresh = false
            coordinator.testingBypassApplyGuards = false
            coordinator.testingConversationListViewModel = nil
            coordinator.clearPendingRoute()
            router.clearPendingChatNavigation()
            router.screen = .splash
        }

        router.screen = .main
        coordinator.configure(router: router, session: session)

        let route = PushNotificationRoute.conversation(
            conversationId: conversationID,
            messageId: firstMessageID,
            senderId: nil
        )
        coordinator.handleRoute(route)

        try? await Task.sleep(for: .milliseconds(200))

        #expect(coordinator.hasPendingRoute)
        #expect(router.selectedMainTab == .chats)
        #expect(router.pendingChatConversation == nil)
    }

    @Test
    func openChatUsesNavigationIdentityForDifferentMessageTargets() {
        let router = AppRouter.shared
        let conversation = makeConversation(id: conversationID)

        defer {
            router.clearPendingChatNavigation()
        }

        router.openChat(conversation, messageID: firstMessageID)
        let firstNavigationID = router.pendingChatNavigationID

        router.openChat(conversation, messageID: secondMessageID)
        let secondNavigationID = router.pendingChatNavigationID

        #expect(firstNavigationID != nil)
        #expect(secondNavigationID != nil)
        #expect(firstNavigationID != secondNavigationID)
        #expect(router.pendingChatMessageID == secondMessageID)
        #expect(router.selectedMainTab == .chats)
    }

    private func makeConversation(id: UUID) -> ChatConversationPreview {
        ChatConversationPreview(
            id: id,
            title: "Alex",
            otherParticipantProfileID: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: "Hi",
            lastSenderName: "Alex",
            lastMessageAt: Date(),
            unreadCount: 1
        )
    }
}
