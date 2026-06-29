import Foundation

enum MessageNotificationPreferences {
    static let messagesEnabledKey = "app.notifications.messages.enabled"
    static let messagePreviewEnabledKey = "app.notifications.messages.preview"

    static var messagesEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: messagesEnabledKey) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: messagesEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: messagesEnabledKey)
        }
    }

    static var messagePreviewEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: messagePreviewEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: messagePreviewEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: messagePreviewEnabledKey)
        }
    }
}
