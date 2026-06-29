import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class MessengerBadgeStore {

    static let shared = MessengerBadgeStore()

    private(set) var unreadCount = 0

    private init() {}

    func setUnreadCount(_ count: Int) {
        let nextCount = max(0, count)
        guard unreadCount != nextCount else { return }

        unreadCount = nextCount
        updateApplicationBadge(nextCount)
    }

    func reset() {
        setUnreadCount(0)
    }

    private func updateApplicationBadge(_ count: Int) {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count) { error in
                if let error {
                    Task { @MainActor in
                        NetworkDebug.logError(error, prefix: "Messenger app badge update failed")
                    }
                }
            }
        } else {
            #if canImport(UIKit)
            UIApplication.shared.applicationIconBadgeNumber = count
            #endif
        }
    }
}
