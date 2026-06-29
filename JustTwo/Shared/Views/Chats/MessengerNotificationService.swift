import Foundation
import UserNotifications
import UIKit

@MainActor
final class MessengerNotificationService {

    static let shared = MessengerNotificationService()
    static var isAppInBackground = false

    enum PayloadKey {
        static let conversationID = "conversationID"
        static let messageID = "messageID"
    }

    private let center = UNUserNotificationCenter.current()
    private let delegate = NotificationDelegate()
    private weak var router: AppRouter?
    private var lastFireAtByConversation: [UUID: Date] = [:]
    private let minInterval: TimeInterval = 1.0

    private init() {}

    func configure(router: AppRouter) {
        self.router = router
        delegate.onOpenMessage = { [weak self] conversationID, messageID in
            Task { @MainActor in
                self?.handleNotificationTap(conversationID: conversationID, messageID: messageID)
            }
        }
        center.delegate = delegate

        Task {
            await requestAuthIfNeeded()
        }
    }

    static func shouldPresentIncomingMessage(
        conversationID: UUID,
        senderProfileID: UUID,
        currentProfileID: UUID,
        activeConversationID: UUID?,
        selectedTab: AppTab
    ) -> Bool {
        guard MessageNotificationPreferences.messagesEnabled else { return false }
        guard senderProfileID != currentProfileID else { return false }
        guard activeConversationID != conversationID else { return false }
        if isAppInBackground { return true }
        return selectedTab != .chats
    }

    func requestAuthIfNeeded() async {
        guard MessageNotificationPreferences.messagesEnabled else { return }

        let status = await authorizationStatus()
        guard status == .notDetermined else { return }
        _ = await requestAuthorization()
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            NetworkDebug.logError(error, prefix: "Messenger notification authorization failed")
            return false
        }
    }

    func presentIncomingMessage(
        conversationID: UUID,
        messageID: UUID,
        partnerName: String,
        previewText: String?,
        avatarPhotoID: UUID?
    ) {
        guard MessageNotificationPreferences.messagesEnabled else { return }
        guard canFire(conversationID: conversationID) else { return }

        Task {
            let status = await authorizationStatus()
            guard status == .authorized || status == .provisional else { return }

            let content = Self.makeContent(
                partnerName: partnerName,
                previewText: previewText,
                avatarPhotoID: avatarPhotoID
            )
            content.threadIdentifier = "conversation:\(conversationID.uuidString)"
            content.userInfo = [
                PayloadKey.conversationID: conversationID.uuidString,
                PayloadKey.messageID: messageID.uuidString
            ]

            if let attachment = Self.makeAvatarAttachment(photoID: avatarPhotoID) {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(
                identifier: messageID.uuidString,
                content: content,
                trigger: nil
            )

            do {
                try await center.add(request)
                NetworkDebug.log("Messenger local notification scheduled: \(conversationID)")
            } catch {
                NetworkDebug.logError(error, prefix: "Messenger local notification failed")
            }
        }
    }

    private func canFire(conversationID: UUID) -> Bool {
        let now = Date()
        if let last = lastFireAtByConversation[conversationID],
           now.timeIntervalSince(last) < minInterval {
            return false
        }
        lastFireAtByConversation[conversationID] = now
        return true
    }

    func handleNotificationTap(conversationID: UUID, messageID: UUID) {
        guard let router else { return }

        let conversation = ConversationListViewModel.shared.conversations
            .first(where: { $0.id == conversationID })
            ?? ChatConversationPreview(
                id: conversationID,
                title: String(localized: "chats.unknownParticipant"),
                avatarURL: nil,
                avatarPhotoID: nil,
                lastMessageText: nil,
                lastSenderName: nil,
                lastMessageAt: nil,
                unreadCount: 0
            )

        router.openChat(conversation, messageID: messageID)
    }

    static func makeContent(
        partnerName: String,
        previewText: String?,
        avatarPhotoID: UUID?
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = partnerName
        content.subtitle = String(localized: "notifications.message.new")
        content.sound = .default

        if MessageNotificationPreferences.messagePreviewEnabled,
           let previewText,
           !previewText.isEmpty {
            content.body = previewText
        }

        return content
    }

    static func makeAvatarAttachment(photoID: UUID?) -> UNNotificationAttachment? {
        guard let photoID,
              let image = ChatPartnerAvatarCache.image(for: photoID),
              let data = image.jpegData(compressionQuality: 0.9) else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-avatar-\(photoID.uuidString).jpg")

        do {
            try data.write(to: url, options: .atomic)
            return try UNNotificationAttachment(
                identifier: "avatar",
                url: url,
                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"]
            )
        } catch {
            return nil
        }
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    var onOpenMessage: ((UUID, UUID) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let conversationRaw = userInfo[MessengerNotificationService.PayloadKey.conversationID] as? String,
              let messageRaw = userInfo[MessengerNotificationService.PayloadKey.messageID] as? String,
              let conversationID = UUID(uuidString: conversationRaw),
              let messageID = UUID(uuidString: messageRaw) else {
            return
        }

        onOpenMessage?(conversationID, messageID)
    }
}
