import Foundation

enum MessengerConnectivityPresentationState: Equatable, Sendable {
    case online
    case offlineShowingCache
    case offlineNoCache
    case refreshing
    case refreshFailedShowingCache
    case syncing
    case syncBackoff
}

struct MessengerUXContext: Equatable, Sendable {
    let isNetworkOffline: Bool
    let sessionConnectivity: SessionConnectivityState
    let syncEngineState: MessengerSyncEngineState
    let hasConversationCache: Bool
    let hasMessageCache: Bool
    let isListRefreshing: Bool
    let isChatRefreshing: Bool
    let lastRefreshFailed: Bool
    let showingConnectionRestoredRefreshing: Bool

    var hasAnyMessengerCache: Bool {
        hasConversationCache || hasMessageCache
    }
}

struct MessengerBannerPresentation: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case validating
        case offlineShowingCache
        case connectionRestoredRefreshing
        case refreshFailed
    }

    let style: Style
    let titleKey: String
    let subtitleKey: String?
    let showsSpinner: Bool

    static let validating = MessengerBannerPresentation(
        style: .validating,
        titleKey: "offline.banner.validating_title",
        subtitleKey: "offline.banner.validating_subtitle",
        showsSpinner: true
    )

    static let offlineShowingCache = MessengerBannerPresentation(
        style: .offlineShowingCache,
        titleKey: "offline.banner.offline_showing_cache",
        subtitleKey: nil,
        showsSpinner: false
    )

    static let connectionRestoredRefreshing = MessengerBannerPresentation(
        style: .connectionRestoredRefreshing,
        titleKey: "offline.banner.connection_restored",
        subtitleKey: nil,
        showsSpinner: true
    )

    static let refreshFailed = MessengerBannerPresentation(
        style: .refreshFailed,
        titleKey: "offline.banner.refresh_failed",
        subtitleKey: "offline.banner.refresh_failed_subtitle",
        showsSpinner: false
    )
}

enum MessengerConnectivityPresentationResolver {

    static func resolve(_ context: MessengerUXContext) -> MessengerConnectivityPresentationState {
        let isSyncActive = context.syncEngineState == .syncing
            || context.syncEngineState == .bootstrapping
        let isBackoff = context.syncEngineState == .backoff
        let syncFailed = context.syncEngineState == .failed
            || context.syncEngineState == .needsFullRefresh
        let offline = context.isNetworkOffline
            || context.sessionConnectivity == .offlineUsingCache
        let hasCache = context.hasAnyMessengerCache

        if context.showingConnectionRestoredRefreshing {
            return .refreshing
        }

        if context.isListRefreshing || context.isChatRefreshing || isSyncActive {
            return hasCache ? .refreshing : (isSyncActive ? .syncing : .refreshing)
        }

        if isBackoff {
            return .syncBackoff
        }

        if syncFailed || context.lastRefreshFailed {
            if hasCache {
                return .refreshFailedShowingCache
            }
        }

        if offline {
            return hasCache ? .offlineShowingCache : .offlineNoCache
        }

        return .online
    }

    static func globalBanner(for context: MessengerUXContext) -> MessengerBannerPresentation? {
        if context.sessionConnectivity == .validationPending {
            return .validating
        }

        if context.showingConnectionRestoredRefreshing {
            return .connectionRestoredRefreshing
        }

        let state = resolve(context)

        switch state {
        case .offlineShowingCache:
            return .offlineShowingCache
        case .refreshFailedShowingCache:
            return .refreshFailed
        case .online, .offlineNoCache, .refreshing, .syncing, .syncBackoff:
            if context.isNetworkOffline, context.hasConversationCache {
                return .offlineShowingCache
            }
            if context.sessionConnectivity == .offlineUsingCache {
                return .offlineShowingCache
            }
            if context.sessionConnectivity == .validationFailedRecoverable,
               context.hasConversationCache,
               context.lastRefreshFailed || state == .refreshFailedShowingCache {
                return .refreshFailed
            }
            return nil
        }
    }

    static func chatsListStatusKey(for context: MessengerUXContext) -> String? {
        let state = resolve(context)

        switch state {
        case .refreshing, .syncing:
            return "messenger.status.refreshing"
        case .offlineShowingCache:
            return "messenger.status.chatsOfflineStale"
        case .refreshFailedShowingCache:
            return "messenger.status.couldNotRefresh"
        case .online:
            if let relative = formattedRelativeUpdate(context) {
                return relative
            }
            return nil
        case .offlineNoCache, .syncBackoff:
            return nil
        }
    }

    static func chatStatusKey(for context: MessengerUXContext) -> String? {
        let state = resolve(context)

        switch state {
        case .refreshing, .syncing:
            return "messenger.status.refreshing"
        case .offlineShowingCache:
            return "messenger.status.chatOfflineShowingSaved"
        case .refreshFailedShowingCache:
            return "messenger.status.couldNotRefresh"
        case .online, .offlineNoCache, .syncBackoff:
            return nil
        }
    }

    static func formattedRelativeUpdate(_ context: MessengerUXContext) -> String? {
        guard let lastSyncAt = MessengerSyncStateStore.shared.lastSyncAt else { return nil }
        let seconds = Date().timeIntervalSince(lastSyncAt)
        if seconds < 60 {
            return "messenger.status.updatedJustNow"
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "messenger.status.updatedMinutesAgo|\(minutes)"
        }
        return nil
    }

    static func localizedStatusText(for key: String?) -> String? {
        guard let key else { return nil }
        if let pipe = key.firstIndex(of: "|") {
            let resourceKey = String(key[..<pipe])
            let value = String(key[key.index(after: pipe)...])
            if let minutes = Int(value) {
                return String(format: String(localized: String.LocalizationValue(resourceKey)), minutes)
            }
            return String(localized: String.LocalizationValue(resourceKey))
        }
        return String(localized: String.LocalizationValue(key))
    }
}
