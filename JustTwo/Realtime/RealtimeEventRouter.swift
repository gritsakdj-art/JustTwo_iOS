import Foundation

@MainActor
@Observable
final class RealtimeEventRouter {

    static let shared = RealtimeEventRouter()

    private var continuations: [UUID: AsyncStream<RealtimeEvent>.Continuation] = [:]
    private(set) var lastEventType: String?

    private init() {}

    static func makeForTesting() -> RealtimeEventRouter {
        RealtimeEventRouter()
    }

    func stream() -> AsyncStream<RealtimeEvent> {
        let id = UUID()

        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [id] _ in
                Task { @MainActor in
                    RealtimeEventRouter.shared.removeContinuation(id)
                }
            }
        }
    }

    func route(_ event: RealtimeEvent) {
        lastEventType = event.type
        NetworkDebug.log("Realtime event received: \(event.type)")

        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}
