import Foundation

@MainActor
final class PushNotificationRoutingCoordinator {

    static let shared = PushNotificationRoutingCoordinator()

    private let parser = PushNotificationPayloadParser()
    private weak var router: AppRouter?
    private weak var session: SessionStore?
    private var pendingRoute: PushNotificationRoute?
    private var lastAppliedRouteKey: String?
    private var applyingRouteKey: String?
    private var lastNotFoundRouteKey: String?
    private var lastNotFoundAt: Date?

    var testingConversationListViewModel: ConversationListViewModel?
    var testingSkipConversationRefresh = false
    var testingBypassApplyGuards = false

    private init() {}

    var hasPendingRoute: Bool {
        pendingRoute != nil
    }

    func configure(router: AppRouter, session: SessionStore) {
        self.router = router
        self.session = session
        PushRegistrationService.shared.onNotificationTap = { [weak self] userInfo in
            Task { @MainActor in
                self?.handleNotification(userInfo: userInfo)
            }
        }
        applyPendingRouteIfPossible()
    }

    func handleNotification(userInfo: [AnyHashable: Any]) {
        NetworkDebug.log("Push notification tap received")

        guard let route = parser.parse(userInfo: userInfo) else {
            NetworkDebug.log("Push notification tap ignored: unsupported or malformed route")
            return
        }

        handleRoute(route)
    }

    func handleRoute(_ route: PushNotificationRoute) {
        switch route {
        case .conversation(let conversationID, let messageID, _):
            NetworkDebug.log(
                "Push route parsed: type=message.created conversationId=\(conversationID.uuidString) messageId=\(messageID?.uuidString ?? "nil")"
            )
        }

        pendingRoute = route
        lastAppliedRouteKey = nil
        lastNotFoundRouteKey = nil
        lastNotFoundAt = nil
        NetworkDebug.log("Push route stored as pending")
        applyPendingRouteIfPossible()
    }

    func clearPendingRoute() {
        pendingRoute = nil
        lastAppliedRouteKey = nil
        applyingRouteKey = nil
        lastNotFoundRouteKey = nil
        lastNotFoundAt = nil
        NetworkDebug.log("Push pending route cleared")
    }

    func applyPendingRouteIfPossible() {
        guard let route = pendingRoute else { return }
        guard let router, let session else {
            NetworkDebug.log("Push route deferred: router/session not configured")
            return
        }
        guard canApplyPendingRoute(session: session, router: router) else { return }

        let routeKey = routeKey(for: route)
        if lastAppliedRouteKey == routeKey {
            return
        }
        if applyingRouteKey != nil {
            NetworkDebug.log("Push route deferred: apply already in flight")
            return
        }

        Task {
            await apply(route: route, routeKey: routeKey, router: router, session: session)
        }
    }

    private func apply(
        route: PushNotificationRoute,
        routeKey: String,
        router: AppRouter,
        session: SessionStore
    ) async {
        guard case .conversation(let conversationID, let messageID, _) = route else { return }
        guard applyingRouteKey == nil else { return }

        applyingRouteKey = routeKey
        defer {
            applyingRouteKey = nil
            if let pendingRoute,
               self.routeKey(for: pendingRoute) != lastAppliedRouteKey {
                applyPendingRouteIfPossible()
            }
        }

        let listViewModel = conversationListViewModel
        var conversation = listViewModel.conversations.first(where: { $0.id == conversationID })

        if conversation == nil {
            let now = Date()
            if lastNotFoundRouteKey == routeKey,
               let lastNotFoundAt,
               now.timeIntervalSince(lastNotFoundAt) < 2 {
                NetworkDebug.log("Push route deferred: recent conversation refresh miss for \(conversationID.uuidString)")
                router.selectedMainTab = .chats
                return
            }

            if !testingSkipConversationRefresh {
                NetworkDebug.log("Push route applying: refreshing conversations for \(conversationID.uuidString)")
                await listViewModel.refresh(session: session, router: router)
                conversation = listViewModel.conversations.first(where: { $0.id == conversationID })
            }
        }

        guard let conversation else {
            NetworkDebug.log("Push route deferred: conversation not found \(conversationID.uuidString)")
            if pendingRouteKey == routeKey {
                lastNotFoundRouteKey = routeKey
                lastNotFoundAt = Date()
            }
            router.selectedMainTab = .chats
            return
        }

        router.openChat(conversation, messageID: messageID)
        lastAppliedRouteKey = routeKey
        if pendingRouteKey == routeKey {
            pendingRoute = nil
            lastNotFoundRouteKey = nil
            lastNotFoundAt = nil
        }
        NetworkDebug.log("Push route applied: conversation \(conversationID.uuidString)")
    }

    private var pendingRouteKey: String? {
        pendingRoute.map(routeKey(for:))
    }

    private var conversationListViewModel: ConversationListViewModel {
        if let testingConversationListViewModel {
            return testingConversationListViewModel
        }
        return ConversationListViewModel.shared
    }

    private func canApplyPendingRoute(session: SessionStore, router: AppRouter) -> Bool {
        if testingBypassApplyGuards {
            return true
        }
        guard session.isFullyAuthenticated else {
            NetworkDebug.log("Push route deferred: session not fully authenticated")
            return false
        }
        guard router.screen == .main else {
            NetworkDebug.log("Push route deferred: main UI not ready")
            return false
        }
        return true
    }

    private func routeKey(for route: PushNotificationRoute) -> String {
        switch route {
        case .conversation(let conversationID, let messageID, _):
            return "\(conversationID.uuidString)-\(messageID?.uuidString ?? "")"
        }
    }
}
