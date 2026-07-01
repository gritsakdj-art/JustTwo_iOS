import Foundation

extension Notification.Name {
    static let messengerConversationMessagesDidChange = Notification.Name("messengerConversationMessagesDidChange")
}

enum MessengerConversationNotification {
  static let conversationIDKey = "conversationID"

  static func postMessagesDidChange(conversationID: UUID) {
    NotificationCenter.default.post(
      name: .messengerConversationMessagesDidChange,
      object: nil,
      userInfo: [conversationIDKey: conversationID]
    )
  }
}
