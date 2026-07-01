import Foundation

enum StartupLoadingLimits {
    nonisolated static let preloadConversationCount = 15
    nonisolated static let preloadMessagesPerConversation = MessengerLimits.defaultMessagePageSize
    nonisolated static let preloadCriticalAvatarCount = 10
}
