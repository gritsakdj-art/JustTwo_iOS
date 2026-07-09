import Foundation

@MainActor
@Observable
final class MessengerUXStatusStore {

    static let shared = MessengerUXStatusStore()

    private(set) var debouncedNetworkOffline = false
    private(set) var connectionRestoredRefreshingUntil: Date?
    private var offlineDebounceTask: Task<Void, Never>?
    private var networkHandlerID: UUID?

    private let offlineShowDebounceMilliseconds = 400
    private let connectionRestoredBannerSeconds: TimeInterval = 4

    private init() {}

    func activate() {
        guard networkHandlerID == nil else { return }
        debouncedNetworkOffline = NetworkPathMonitor.shared.shouldSkipNetworkBecauseOffline
        networkHandlerID = NetworkPathMonitor.shared.registerPathChangeHandler { [weak self] in
            self?.handleNetworkPathChange()
        }
    }

    func deactivate() {
        offlineDebounceTask?.cancel()
        offlineDebounceTask = nil
        if let networkHandlerID {
            NetworkPathMonitor.shared.unregisterHandler(networkHandlerID)
            self.networkHandlerID = nil
        }
    }

    var shouldShowGlobalBanner: Bool {
        globalBannerPresentation != nil
    }

    var globalBannerPresentation: MessengerBannerPresentation? {
        MessengerConnectivityPresentationResolver.globalBanner(
            for: makeGlobalContext(
                listViewModel: ConversationListViewModel.shared,
                session: SessionStore.shared
            )
        )
    }

    func chatsListStatusText(
        listViewModel: ConversationListViewModel,
        session: SessionStore
    ) -> String? {
        MessengerConnectivityPresentationResolver.localizedStatusText(
            for: MessengerConnectivityPresentationResolver.chatsListStatusKey(
                for: makeListContext(listViewModel: listViewModel, session: session)
            )
        )
    }

    func chatStatusText(
        chatViewModel: ChatViewModel,
        session: SessionStore
    ) -> String? {
        MessengerConnectivityPresentationResolver.localizedStatusText(
            for: MessengerConnectivityPresentationResolver.chatStatusKey(
                for: makeChatContext(chatViewModel: chatViewModel, session: session)
            )
        )
    }

    func presentationState(
        listViewModel: ConversationListViewModel,
        session: SessionStore
    ) -> MessengerConnectivityPresentationState {
        MessengerConnectivityPresentationResolver.resolve(
            makeListContext(listViewModel: listViewModel, session: session)
        )
    }

    func makeGlobalContext(
        listViewModel: ConversationListViewModel,
        session: SessionStore
    ) -> MessengerUXContext {
        makeListContext(listViewModel: listViewModel, session: session)
    }

    func makeListContext(
        listViewModel: ConversationListViewModel,
        session: SessionStore
    ) -> MessengerUXContext {
        MessengerUXContext(
            isNetworkOffline: debouncedNetworkOffline,
            sessionConnectivity: session.connectivityState,
            syncEngineState: MessengerSyncEngine.shared.state,
            hasConversationCache: listViewModel.hasCachedConversations,
            hasMessageCache: false,
            isListRefreshing: listViewModel.isRefreshingNetwork,
            isChatRefreshing: false,
            lastRefreshFailed: listViewModel.lastNetworkRefreshFailed
                || MessengerSyncEngine.shared.state == .failed
                || MessengerSyncEngine.shared.state == .needsFullRefresh,
            showingConnectionRestoredRefreshing: isShowingConnectionRestoredRefreshing
        )
    }

    func makeChatContext(
        chatViewModel: ChatViewModel,
        session: SessionStore
    ) -> MessengerUXContext {
        MessengerUXContext(
            isNetworkOffline: debouncedNetworkOffline,
            sessionConnectivity: session.connectivityState,
            syncEngineState: MessengerSyncEngine.shared.state,
            hasConversationCache: ConversationListViewModel.shared.hasCachedConversations,
            hasMessageCache: chatViewModel.hasCachedMessages,
            isListRefreshing: false,
            isChatRefreshing: chatViewModel.isNetworkRefreshingMessages,
            lastRefreshFailed: chatViewModel.lastNetworkRefreshFailed
                || MessengerSyncEngine.shared.state == .failed
                || MessengerSyncEngine.shared.state == .needsFullRefresh,
            showingConnectionRestoredRefreshing: isShowingConnectionRestoredRefreshing
        )
    }

    private var isShowingConnectionRestoredRefreshing: Bool {
        guard let connectionRestoredRefreshingUntil else { return false }
        if connectionRestoredRefreshingUntil > Date() {
            return true
        }
        self.connectionRestoredRefreshingUntil = nil
        return false
    }

    private func handleNetworkPathChange() {
        let offline = NetworkPathMonitor.shared.shouldSkipNetworkBecauseOffline

        if offline {
            offlineDebounceTask?.cancel()
            offlineDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(self?.offlineShowDebounceMilliseconds ?? 400))
                guard !Task.isCancelled else { return }
                self?.debouncedNetworkOffline = true
                self?.connectionRestoredRefreshingUntil = nil
            }
            return
        }

        offlineDebounceTask?.cancel()
        offlineDebounceTask = nil
        let wasOffline = debouncedNetworkOffline
        debouncedNetworkOffline = false

        if wasOffline {
            connectionRestoredRefreshingUntil = Date().addingTimeInterval(connectionRestoredBannerSeconds)
        }
    }

    #if DEBUG
    func setDebouncedNetworkOfflineForTesting(_ offline: Bool) {
        debouncedNetworkOffline = offline
    }

    func setConnectionRestoredRefreshingForTesting(until date: Date?) {
        connectionRestoredRefreshingUntil = date
    }
    #endif
}
