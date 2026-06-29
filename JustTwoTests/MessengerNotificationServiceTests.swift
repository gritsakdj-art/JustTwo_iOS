import Foundation
import Testing
import UserNotifications
@testable import JustTwo

@MainActor
struct MessengerNotificationServiceTests {

    @Test
    func contentIncludesPartnerNameAndNewMessageSubtitle() {
        MessageNotificationPreferences.messagePreviewEnabled = true

        let content = MessengerNotificationService.makeContent(
            partnerName: "Emma",
            previewText: "Hello there",
            avatarPhotoID: nil
        )

        #expect(content.title == "Emma")
        #expect(content.subtitle == String(localized: "notifications.message.new"))
        #expect(content.body == "Hello there")
    }

    @Test
    func contentOmitsPreviewWhenDisabled() {
        MessageNotificationPreferences.messagePreviewEnabled = false

        let content = MessengerNotificationService.makeContent(
            partnerName: "Emma",
            previewText: "Hello there",
            avatarPhotoID: nil
        )

        #expect(content.title == "Emma")
        #expect(content.subtitle == String(localized: "notifications.message.new"))
        #expect(content.body.isEmpty)
    }

    @Test
    func shouldPresentOnOtherTabsButNotChatsTab() {
        let previousEnabled = MessageNotificationPreferences.messagesEnabled
        let previousBackground = MessengerNotificationService.isAppInBackground
        defer {
            MessageNotificationPreferences.messagesEnabled = previousEnabled
            MessengerNotificationService.isAppInBackground = previousBackground
        }

        MessageNotificationPreferences.messagesEnabled = true
        MessengerNotificationService.isAppInBackground = false

        let conversationID = UUID()
        let currentProfileID = UUID()
        let senderProfileID = UUID()

        #expect(
            MessengerNotificationService.shouldPresentIncomingMessage(
                conversationID: conversationID,
                senderProfileID: senderProfileID,
                currentProfileID: currentProfileID,
                activeConversationID: nil,
                selectedTab: .discover
            )
        )

        #expect(
            !MessengerNotificationService.shouldPresentIncomingMessage(
                conversationID: conversationID,
                senderProfileID: senderProfileID,
                currentProfileID: currentProfileID,
                activeConversationID: nil,
                selectedTab: .chats
            )
        )
    }

    @Test
    func shouldPresentInBackgroundEvenOnChatsTab() {
        let previousEnabled = MessageNotificationPreferences.messagesEnabled
        let previousBackground = MessengerNotificationService.isAppInBackground
        defer {
            MessageNotificationPreferences.messagesEnabled = previousEnabled
            MessengerNotificationService.isAppInBackground = previousBackground
        }

        MessageNotificationPreferences.messagesEnabled = true
        MessengerNotificationService.isAppInBackground = true

        let conversationID = UUID()
        let currentProfileID = UUID()
        let senderProfileID = UUID()

        #expect(
            MessengerNotificationService.shouldPresentIncomingMessage(
                conversationID: conversationID,
                senderProfileID: senderProfileID,
                currentProfileID: currentProfileID,
                activeConversationID: nil,
                selectedTab: .chats
            )
        )

        MessengerNotificationService.isAppInBackground = false
    }

    @Test
    func shouldNotPresentForOwnMessagesOrOpenConversation() {
        let previousEnabled = MessageNotificationPreferences.messagesEnabled
        let previousBackground = MessengerNotificationService.isAppInBackground
        defer {
            MessageNotificationPreferences.messagesEnabled = previousEnabled
            MessengerNotificationService.isAppInBackground = previousBackground
        }

        MessageNotificationPreferences.messagesEnabled = true
        MessengerNotificationService.isAppInBackground = false

        let conversationID = UUID()
        let currentProfileID = UUID()

        #expect(
            !MessengerNotificationService.shouldPresentIncomingMessage(
                conversationID: conversationID,
                senderProfileID: currentProfileID,
                currentProfileID: currentProfileID,
                activeConversationID: nil,
                selectedTab: .discover
            )
        )

        #expect(
            !MessengerNotificationService.shouldPresentIncomingMessage(
                conversationID: conversationID,
                senderProfileID: UUID(),
                currentProfileID: currentProfileID,
                activeConversationID: conversationID,
                selectedTab: .discover
            )
        )
    }
}
