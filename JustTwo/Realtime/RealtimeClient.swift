import Foundation

@MainActor
final class RealtimeClient {

    static let shared = RealtimeClient(
        router: RealtimeEventRouter.shared
    )

    private(set) var state: RealtimeConnectionState = .disconnected

    private let configuration: APIConfiguration
    private let sessionProvider: @MainActor () -> URLSession
    private let router: RealtimeEventRouter
    private let reconnectPolicy: RealtimeReconnectPolicy
    private let tokenProvider: @MainActor () -> String?

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var receiveConnectionContext: RealtimeConnectionContext?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var explicitDisconnect = true
    private var isDisconnectingExplicitly = false
    private var foregroundAllowed = true
    private var pendingSubscribeConversationIDs: Set<UUID> = []
    private var pendingUnsubscribeConversationIDs: Set<UUID> = []
    private var keepaliveTask: Task<Void, Never>?
    private var needsForegroundReconnect = false
    private var socketGeneration = 0

    private let backgroundKeepaliveInterval: TimeInterval = 20

    private var sessionsResetObserver: NSObjectProtocol?

    init(
        configuration: APIConfiguration = .current,
        session: URLSession? = nil,
        router: RealtimeEventRouter,
        reconnectPolicy: RealtimeReconnectPolicy = .default,
        tokenProvider: @escaping @MainActor () -> String? = { APIAuth.accessToken }
    ) {
        self.configuration = configuration
        if let session {
            self.sessionProvider = { session }
        } else {
            self.sessionProvider = { URLSessionProvider.session }
        }
        self.router = router
        self.reconnectPolicy = reconnectPolicy
        self.tokenProvider = tokenProvider

        sessionsResetObserver = NotificationCenter.default.addObserver(
            forName: .urlSessionsDidReset,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleNetworkingSessionsReset()
            }
        }
    }

    deinit {
        if let sessionsResetObserver {
            NotificationCenter.default.removeObserver(sessionsResetObserver)
        }
    }

    func connect(jwt: String) async {
        guard !jwt.isEmpty else {
            state = .failed(message: "Missing realtime token")
            return
        }

        guard task == nil else {
            NetworkDebug.log("Realtime connect skipped: socket already exists")
            return
        }

        explicitDisconnect = false
        isDisconnectingExplicitly = false
        reconnectTask?.cancel()
        reconnectTask = nil
        state = reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: reconnectAttempt)

        var request = URLRequest(url: configuration.realtimeWebSocketURL)
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        NetworkDebug.log("Realtime connect start")
        MessengerDiagnostics.event(
            .realtimeConnectRequested,
            metadata: [
                "connectionState": reconnectAttempt == 0 ? "connecting" : "reconnecting",
                "retryAttempt": "\(reconnectAttempt)"
            ]
        )

        let socket = sessionProvider().webSocketTask(with: request)
        socketGeneration += 1
        let generation = socketGeneration
        task = socket
        let connectionContext = RealtimeTransportGuard.beginConnection(presenceStore: .shared)
        receiveConnectionContext = connectionContext
        socket.resume()

        startReceiveLoop(for: socket, context: connectionContext, generation: generation)
    }

    func connectIfPossible() async {
        guard foregroundAllowed else {
            NetworkDebug.log("Realtime connect skipped: app is not foreground active")
            return
        }

        guard let token = tokenProvider(), !token.isEmpty else {
            NetworkDebug.log("Realtime connect skipped: missing JWT")
            state = .disconnected
            return
        }

        await connect(jwt: token)
    }

    func disconnect() {
        disconnect(shouldReconnect: false)
    }

    func applicationDidBecomeActive() {
        foregroundAllowed = true
        stopBackgroundKeepalive()

        Task { [weak self] in
            await self?.refreshConnectionAfterForeground()
        }
    }

    func applicationDidEnterBackground() {
        guard shouldMaintainBackgroundConnection else {
            stopBackgroundKeepalive()
            foregroundAllowed = false
            disconnect(shouldReconnect: false)
            return
        }

        NetworkDebug.log("Realtime background disconnect skipped: message notifications enabled")
        needsForegroundReconnect = true
        startBackgroundKeepalive()
    }

    func sendPing() async throws {
        try await send(.ping())
    }

    func subscribe(conversationID: UUID) async throws {
        pendingUnsubscribeConversationIDs.remove(conversationID)

        guard let task, case .connected = state else {
            pendingSubscribeConversationIDs.insert(conversationID)
            NetworkDebug.log("Realtime subscribe queued until connected: \(conversationID)")
            throw RealtimeClientError.notConnected
        }

        pendingSubscribeConversationIDs.remove(conversationID)
        let generation = socketGeneration
        try await send(.subscribe(conversationID: conversationID), using: task, generation: generation)
    }

    func unsubscribe(conversationID: UUID) async throws {
        pendingSubscribeConversationIDs.remove(conversationID)

        guard let task, case .connected = state else {
            pendingUnsubscribeConversationIDs.insert(conversationID)
            NetworkDebug.log("Realtime unsubscribe queued until connected: \(conversationID)")
            throw RealtimeClientError.notConnected
        }

        pendingUnsubscribeConversationIDs.remove(conversationID)
        let generation = socketGeneration
        try await send(.unsubscribe(conversationID: conversationID), using: task, generation: generation)
    }

    func sendTypingStarted(conversationID: UUID) async throws {
        try await send(.typingStarted(conversationID: conversationID))
    }

    func sendTypingStopped(conversationID: UUID) async throws {
        try await send(.typingStopped(conversationID: conversationID))
    }

    private func send(_ message: RealtimeClientMessageDTO) async throws {
        guard let task else {
            throw RealtimeClientError.notConnected
        }

        let generation = socketGeneration
        try await send(message, using: task, generation: generation)
    }

    private func send(
        _ message: RealtimeClientMessageDTO,
        using task: URLSessionWebSocketTask,
        generation: Int
    ) async throws {
        guard socketGeneration == generation, self.task === task else {
            throw RealtimeClientError.notConnected
        }

        let data = try JSONCoding.encoder.encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RealtimeClientError.encodingFailed
        }

        do {
            guard socketGeneration == generation, self.task === task else {
                throw RealtimeClientError.notConnected
            }
            try await task.send(.string(text))
            guard socketGeneration == generation, self.task === task else {
                NetworkDebug.log("Realtime send completed for stale socket: \(message.type)")
                return
            }
            NetworkDebug.log("Realtime send succeeded: \(message.type)")
        } catch {
            if socketGeneration != generation || self.task !== task || explicitDisconnect || isDisconnectingExplicitly {
                NetworkDebug.log("Realtime send ignored for stale/disconnecting socket: \(message.type)")
                throw RealtimeClientError.notConnected
            }
            NetworkDebug.logError(error, prefix: "Realtime send failed")
            scheduleReconnectIfNeeded()
            throw error
        }
    }

    private func startReceiveLoop(
        for socket: URLSessionWebSocketTask,
        context: RealtimeConnectionContext,
        generation: Int
    ) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self, weak socket] in
            guard let socket else { return }

            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    let isCurrentSocket = await MainActor.run { [weak self] in
                        guard let self else { return false }
                        return self.socketGeneration == generation && self.task === socket
                    }
                    guard isCurrentSocket else {
                        NetworkDebug.log("Realtime receive ignored for stale socket generation=\(generation)")
                        return
                    }
                    await self?.handle(message, context: context)
                } catch is CancellationError {
                    return
                } catch {
                    let shouldHandleError = await MainActor.run { [weak self] in
                        guard let self else { return false }
                        return self.socketGeneration == generation && self.task === socket
                    }
                    guard shouldHandleError else {
                        NetworkDebug.log("Realtime receive error ignored for stale socket generation=\(generation)")
                        return
                    }
                    await MainActor.run { [weak self] in
                        self?.handleReceiveError(error)
                    }
                    return
                }
            }
        }
    }

    private func handle(
        _ message: URLSessionWebSocketTask.Message,
        context: RealtimeConnectionContext
    ) async {
        switch message {
        case .string(let text):
            decodeAndRoute(text, context: context)

        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                NetworkDebug.log("Realtime received non-UTF8 data message")
                return
            }
            decodeAndRoute(text, context: context)

        @unknown default:
            NetworkDebug.log("Realtime received unknown WebSocket message")
        }
    }

    private func decodeAndRoute(_ text: String, context: RealtimeConnectionContext) {
        do {
            let dto = try JSONCoding.decoder.decode(RealtimeEventDTO.self, from: Data(text.utf8))
            let event = dto.event
            guard RealtimeTransportGuard.accepts(context, presenceStore: .shared) else {
                RealtimeTransportGuard.logIgnoredEvent(event, context: context, presenceStore: .shared)
                return
            }
            handleConnectionState(for: event)
            router.route(event, context: context)
        } catch {
            NetworkDebug.logError(error, prefix: "Realtime decode failed")
        }
    }

    private func handleConnectionState(for event: RealtimeEvent) {
        switch event {
        case .connectionReady(let payload):
            reconnectAttempt = 0
            state = .connected(connectionID: payload.connectionID)
            NetworkDebug.log("Realtime connection ready")
            MessengerDiagnostics.event(
                .realtimeConnectionReady,
                metadata: [
                    "connectionState": "connected",
                    "hasConnectionID": payload.connectionID == nil ? "false" : "true"
                ]
            )
            Task { [weak self] in
                await self?.flushPendingSubscriptions()
            }

        case .error(let payload) where payload.code == "unauthorized":
            state = .failed(message: payload.message)
            disconnect(shouldReconnect: false)

        case .error(let payload):
            NetworkDebug.log("Realtime error event: \(payload.code)")

        default:
            break
        }
    }

    private func handleReceiveError(_ error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
            NetworkDebug.log("Realtime receive loop cancelled")
            return
        }

        if shouldSuppressReceiveErrorAfterIntentionalDisconnect {
            NetworkDebug.log("Realtime receive loop stopped after intentional disconnect")
            receiveTask = nil
            return
        }

        NetworkDebug.logError(error, prefix: "Realtime receive failed")
        task = nil
        receiveTask = nil

        let isTimeout = ns.domain == NSURLErrorDomain && ns.code == NSURLErrorTimedOut
        scheduleReconnectIfNeeded(
            immediate: isTimeout && shouldMaintainBackgroundConnection
        )
    }

    private func handleNetworkingSessionsReset() {
        guard task != nil || reconnectTask != nil else { return }
        NetworkDebug.log("Realtime reconnecting after URL session reset")
        disconnect(shouldReconnect: true)
    }

    private func disconnect(shouldReconnect: Bool) {
        socketGeneration += 1
        explicitDisconnect = !shouldReconnect
        isDisconnectingExplicitly = !shouldReconnect
        reconnectTask?.cancel()
        reconnectTask = nil
        stopBackgroundKeepalive()

        receiveTask?.cancel()
        receiveTask = nil
        receiveConnectionContext = nil
        RealtimeTransportGuard.invalidateActiveConnection()

        let oldTask = task
        task = nil
        oldTask?.cancel(with: .normalClosure, reason: nil)
        pendingSubscribeConversationIDs.removeAll()
        pendingUnsubscribeConversationIDs.removeAll()

        if shouldReconnect {
            isDisconnectingExplicitly = false
            scheduleReconnectIfNeeded()
        } else {
            reconnectAttempt = 0
            state = .disconnected
            PresenceStore.shared.clearAll()
            NetworkDebug.log("Realtime disconnected")
            MessengerDiagnostics.event(
                .realtimeDisconnected,
                metadata: [
                    "reason": "explicitDisconnect",
                    "connectionState": "disconnected"
                ]
            )
        }
    }

    private var shouldSuppressReceiveErrorAfterIntentionalDisconnect: Bool {
        explicitDisconnect || isDisconnectingExplicitly
    }

    private func scheduleReconnectIfNeeded(immediate: Bool = false) {
        guard !explicitDisconnect, foregroundAllowed || shouldMaintainBackgroundConnection else {
            state = .disconnected
            return
        }

        guard tokenProvider() != nil else {
            state = .disconnected
            return
        }

        guard reconnectTask == nil else { return }

        reconnectAttempt += 1
        let attempt = reconnectAttempt
        let delay = immediate ? 0 : reconnectPolicy.delay(forAttempt: attempt)
        state = .reconnecting(attempt: attempt)

        NetworkDebug.log("Realtime reconnect scheduled attempt=\(attempt) delay=\(delay)s")
        MessengerDiagnostics.event(
            .realtimeReconnectScheduled,
            metadata: [
                "retryAttempt": "\(attempt)",
                "durationMs": "\(Int(delay * 1_000))",
                "connectionState": "reconnecting"
            ]
        )

        reconnectTask = Task { [weak self] in
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.reconnectTask = nil
                Task { [weak self] in
                    await self?.connectIfPossible()
                }
            }
        }
    }

    private var shouldMaintainBackgroundConnection: Bool {
        MessageNotificationPreferences.messagesEnabled
    }

    private func refreshConnectionAfterForeground() async {
        defer { needsForegroundReconnect = false }

        if needsForegroundReconnect {
            NetworkDebug.log("Realtime foreground refresh reconnect started")
            if task != nil {
                disconnect(shouldReconnect: false)
            }
            await connectIfPossible()
            return
        }

        if task == nil {
            await connectIfPossible()
            return
        }

        do {
            try await sendPing()
            NetworkDebug.log("Realtime foreground ping succeeded")
        } catch {
            NetworkDebug.logError(error, prefix: "Realtime foreground ping failed, reconnecting")
            disconnect(shouldReconnect: false)
            await connectIfPossible()
        }
    }

    private func startBackgroundKeepalive() {
        stopBackgroundKeepalive()

        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.backgroundKeepaliveInterval ?? 20))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self, self.task != nil else { return }

                    Task {
                        do {
                            try await self.sendPing()
                            NetworkDebug.log("Realtime background ping succeeded")
                        } catch {
                            NetworkDebug.logError(error, prefix: "Realtime background ping failed")
                            self.handleReceiveError(error)
                        }
                    }
                }
            }
        }
    }

    private func stopBackgroundKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
    }

    private func flushPendingSubscriptions() async {
        guard let task, case .connected = state else { return }

        let generation = socketGeneration
        let subscribeIDs = pendingSubscribeConversationIDs
        let unsubscribeIDs = pendingUnsubscribeConversationIDs
        pendingSubscribeConversationIDs.removeAll()
        pendingUnsubscribeConversationIDs.removeAll()

        for conversationID in unsubscribeIDs {
            guard socketGeneration == generation, self.task === task else {
                pendingUnsubscribeConversationIDs.insert(conversationID)
                return
            }
            do {
                try await send(.unsubscribe(conversationID: conversationID), using: task, generation: generation)
                NetworkDebug.log("Realtime flushed queued unsubscribe: \(conversationID)")
            } catch {
                pendingUnsubscribeConversationIDs.insert(conversationID)
                NetworkDebug.logError(error, prefix: "Realtime flushed unsubscribe failed")
            }
        }

        for conversationID in subscribeIDs {
            guard socketGeneration == generation, self.task === task else {
                pendingSubscribeConversationIDs.insert(conversationID)
                return
            }
            do {
                try await send(.subscribe(conversationID: conversationID), using: task, generation: generation)
                NetworkDebug.log("Realtime flushed queued subscribe: \(conversationID)")
            } catch {
                pendingSubscribeConversationIDs.insert(conversationID)
                NetworkDebug.logError(error, prefix: "Realtime flushed subscribe failed")
            }
        }
    }
}

#if DEBUG
extension RealtimeClient {
    var hasPendingReconnectForTesting: Bool {
        reconnectTask != nil
    }

    func simulateActiveConnectionForTesting() {
        explicitDisconnect = false
        isDisconnectingExplicitly = false
        foregroundAllowed = true
        reconnectAttempt = 0
        state = .connected(connectionID: nil)
    }

    func simulateReceiveErrorForTesting(_ error: Error) {
        handleReceiveError(error)
    }
}
#endif

enum RealtimeClientError: LocalizedError {
    case notConnected
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Realtime socket is not connected."
        case .encodingFailed:
            return "Realtime message encoding failed."
        }
    }
}
