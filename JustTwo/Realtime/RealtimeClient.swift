import Foundation

@MainActor
final class RealtimeClient {

    static let shared = RealtimeClient(
        router: RealtimeEventRouter.shared
    )

    private(set) var state: RealtimeConnectionState = .disconnected

    private let configuration: APIConfiguration
    private let session: URLSession
    private let router: RealtimeEventRouter
    private let reconnectPolicy: RealtimeReconnectPolicy
    private let tokenProvider: @MainActor () -> String?

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var explicitDisconnect = true
    private var isDisconnectingExplicitly = false
    private var foregroundAllowed = true

    init(
        configuration: APIConfiguration = .current,
        session: URLSession = URLSessionProvider.session,
        router: RealtimeEventRouter,
        reconnectPolicy: RealtimeReconnectPolicy = .default,
        tokenProvider: @escaping @MainActor () -> String? = { APIAuth.accessToken }
    ) {
        self.configuration = configuration
        self.session = session
        self.router = router
        self.reconnectPolicy = reconnectPolicy
        self.tokenProvider = tokenProvider
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

        let socket = session.webSocketTask(with: request)
        task = socket
        socket.resume()

        startReceiveLoop(for: socket)
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
        Task { [weak self] in
            await self?.connectIfPossible()
        }
    }

    func applicationDidEnterBackground() {
        foregroundAllowed = false
        disconnect(shouldReconnect: false)
    }

    func sendPing() async throws {
        try await send(.ping())
    }

    func subscribe(conversationID: UUID) async throws {
        try await send(.subscribe(conversationID: conversationID))
    }

    func unsubscribe(conversationID: UUID) async throws {
        try await send(.unsubscribe(conversationID: conversationID))
    }

    private func send(_ message: RealtimeClientMessageDTO) async throws {
        guard let task else {
            throw RealtimeClientError.notConnected
        }

        let data = try JSONCoding.encoder.encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RealtimeClientError.encodingFailed
        }

        do {
            try await task.send(.string(text))
            NetworkDebug.log("Realtime send succeeded: \(message.type)")
        } catch {
            NetworkDebug.logError(error, prefix: "Realtime send failed")
            scheduleReconnectIfNeeded()
            throw error
        }
    }

    private func startReceiveLoop(for socket: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self, weak socket] in
            guard let socket else { return }

            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    await self?.handle(message)
                } catch is CancellationError {
                    return
                } catch {
                    guard let self else { return }
                    await MainActor.run {
                        self.handleReceiveError(error)
                    }
                    return
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            decodeAndRoute(text)

        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                NetworkDebug.log("Realtime received non-UTF8 data message")
                return
            }
            decodeAndRoute(text)

        @unknown default:
            NetworkDebug.log("Realtime received unknown WebSocket message")
        }
    }

    private func decodeAndRoute(_ text: String) {
        do {
            let dto = try JSONCoding.decoder.decode(RealtimeEventDTO.self, from: Data(text.utf8))
            let event = dto.event
            handleConnectionState(for: event)
            router.route(event)
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
        scheduleReconnectIfNeeded()
    }

    private func disconnect(shouldReconnect: Bool) {
        explicitDisconnect = !shouldReconnect
        isDisconnectingExplicitly = !shouldReconnect
        reconnectTask?.cancel()
        reconnectTask = nil

        receiveTask?.cancel()
        receiveTask = nil

        task?.cancel(with: .normalClosure, reason: nil)
        task = nil

        if shouldReconnect {
            isDisconnectingExplicitly = false
            scheduleReconnectIfNeeded()
        } else {
            reconnectAttempt = 0
            state = .disconnected
            NetworkDebug.log("Realtime disconnected")
        }
    }

    private var shouldSuppressReceiveErrorAfterIntentionalDisconnect: Bool {
        explicitDisconnect || isDisconnectingExplicitly
    }

    private func scheduleReconnectIfNeeded() {
        guard !explicitDisconnect, foregroundAllowed else {
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
        let delay = reconnectPolicy.delay(forAttempt: attempt)
        state = .reconnecting(attempt: attempt)

        NetworkDebug.log("Realtime reconnect scheduled attempt=\(attempt) delay=\(delay)s")

        reconnectTask = Task { [weak self] in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)

            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.reconnectTask = nil
                Task { [weak self] in
                    await self?.connectIfPossible()
                }
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
