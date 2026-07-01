import Foundation
import Testing
@testable import JustTwo

/// Covers the PR12C fix: a chat should never stay empty just because a load happened to be
/// in-flight elsewhere (startup preload, another ChatViewModel instance, etc). `ChatViewModel`
/// now listens for `MessengerConversationNotification` cache updates for as long as it's open,
/// and `MessageCacheStore.mergeLoadedMessages` posts that notification (synchronously, via
/// `queue: nil`) after every merge so any active chat resyncs immediately instead of relying on
/// the user pulling to refresh.
///
/// Each test uses its own conversation id (rather than the shared fixture id used elsewhere in
/// this file/target) because `MessageCacheStore.shared` is a process-wide singleton and
/// `reset()` clears every conversation's entry; using unique ids keeps these tests independent
/// even if the test runner schedules them alongside other suites.
@MainActor
@Suite("Chat Initial Load Tests")
struct ChatInitialLoadTests {

    @Test("cache notification syncs messages into an already-open chat")
    func cacheNotificationSyncsMessagesIntoOpenChatViewModel() {
        let store = MessageCacheStore.shared
        let conversationID = uniqueConversationID()

        let conversation = makeConversation(id: conversationID)
        let existing = makeMessage(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_000))
        store.setMessages([existing], for: conversationID)

        let viewModel = ChatViewModel.preview(conversation: conversation, messages: [existing])
        #expect(viewModel.messages.count == 1)

        // Simulate a load that this ChatViewModel did NOT itself await (e.g. startup preload,
        // or a second ChatViewModel instance that deduplicated against an in-flight fetch).
        let incoming = makeMessage(id: UUID(), createdAt: Date(timeIntervalSince1970: 2_000))
        store.mergeLoadedMessages([existing, incoming], for: conversationID)

        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages.contains(where: { $0.id == incoming.id }))
    }

    @Test("cache notification for a different conversation is ignored")
    func cacheNotificationForDifferentConversationIsIgnored() {
        let store = MessageCacheStore.shared
        let conversationID = uniqueConversationID()
        let otherConversationID = uniqueConversationID()

        let conversation = makeConversation(id: conversationID)
        let existing = makeMessage(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_000))
        let viewModel = ChatViewModel.preview(conversation: conversation, messages: [existing])

        store.setMessages(
            [existing, makeMessage(id: UUID(), createdAt: .now)],
            for: otherConversationID
        )
        MessengerConversationNotification.postMessagesDidChange(conversationID: otherConversationID)

        #expect(viewModel.messages.count == 1)
    }

    @Test("cache notification preserves pending optimistic message")
    func cacheNotificationPreservesPendingOptimisticMessage() {
        let store = MessageCacheStore.shared
        let conversationID = uniqueConversationID()

        let conversation = makeConversation(id: conversationID)
        let clientMessageID = UUID().uuidString
        let pending = ChatMessage.optimisticOutgoing(
            clientMessageID: clientMessageID,
            body: "Still sending",
            replyPreview: nil,
            createdAt: Date(timeIntervalSince1970: 3_000)
        )
        store.setMessages([pending], for: conversationID)

        let viewModel = ChatViewModel.preview(conversation: conversation, messages: [pending])
        #expect(viewModel.messages.count == 1)

        let olderFromServer = makeMessage(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_000))
        store.mergeLoadedMessages([olderFromServer], for: conversationID)

        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages.contains {
            $0.clientMessageID == clientMessageID && $0.localSendState == .sending
        })
    }

    @Test("cache notification preserves failed optimistic message")
    func cacheNotificationPreservesFailedOptimisticMessage() {
        let store = MessageCacheStore.shared
        let conversationID = uniqueConversationID()

        let conversation = makeConversation(id: conversationID)
        let clientMessageID = UUID().uuidString
        let failed = ChatMessage.optimisticOutgoing(
            clientMessageID: clientMessageID,
            body: "Could not send",
            replyPreview: nil,
            createdAt: Date(timeIntervalSince1970: 3_000)
        ).replacingLocalSendState(.failed)
        store.setMessages([failed], for: conversationID)

        let viewModel = ChatViewModel.preview(conversation: conversation, messages: [failed])

        store.mergeLoadedMessages([], for: conversationID)

        #expect(viewModel.messages.contains {
            $0.clientMessageID == clientMessageID && $0.localSendState == .failed
        })
    }

    @Test("closed chat stops receiving cache notifications")
    func closedChatStopsReceivingCacheNotifications() {
        let store = MessageCacheStore.shared
        let conversationID = uniqueConversationID()

        let conversation = makeConversation(id: conversationID)
        let existing = makeMessage(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_000))
        let viewModel = ChatViewModel.preview(conversation: conversation, messages: [existing])

        viewModel.close()

        let incoming = makeMessage(id: UUID(), createdAt: Date(timeIntervalSince1970: 2_000))
        store.mergeLoadedMessages([existing, incoming], for: conversationID)

        // The observer was torn down on close(); a stale/closed chat must not silently mutate
        // its message list from background cache activity.
        #expect(viewModel.messages.count == 1)
    }

    @Test("reopening the same ChatViewModel resumes cache notification delivery")
    func reopenResumesCacheNotificationDelivery() async {
        let store = MessageCacheStore.shared
        let conversationID = uniqueConversationID()

        let conversation = makeConversation(id: conversationID, unreadCount: 0)
        let existing = makeMessage(id: UUID(), isMine: true, createdAt: Date(timeIntervalSince1970: 1_000))
        let viewModel = ChatViewModel.preview(conversation: conversation, messages: [existing])

        viewModel.close()

        // Re-open the same instance the way a tab switch / background-foreground cycle would,
        // without recreating the ChatViewModel. All messages are `isMine` so markDelivered/markRead
        // both no-op locally without requiring network.
        await viewModel.open(session: .shared, router: .shared)

        let incoming = makeMessage(id: UUID(), isMine: true, createdAt: Date(timeIntervalSince1970: 2_000))
        store.mergeLoadedMessages([existing, incoming], for: conversationID)

        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages.contains(where: { $0.id == incoming.id }))
    }

    private func uniqueConversationID() -> UUID {
        UUID()
    }

    private func makeConversation(id: UUID, unreadCount: Int = 0) -> ChatConversationPreview {
        ChatConversationPreview(
            id: id,
            title: "Taylor",
            otherParticipantProfileID: UUID(uuidString: "55555555-5555-4555-8555-555555555555"),
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: "Hello",
            lastSenderName: nil,
            lastMessageAt: Date(),
            unreadCount: unreadCount
        )
    }

    private func makeMessage(
        id: UUID,
        isMine: Bool = false,
        createdAt: Date
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            displayText: "Message",
            rawBody: "Message",
            createdAt: createdAt,
            isMine: isMine,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: [],
            deliveryStatus: isMine ? .sent : nil
        )
    }
}
