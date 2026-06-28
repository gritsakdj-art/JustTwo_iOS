import Foundation

@MainActor
@Observable
final class RealtimeEventRouter {

    static let shared = RealtimeEventRouter()

    private var continuations: [UUID: AsyncStream<RealtimeEvent>.Continuation] = [:]
    private(set) var lastEventType: String?

    private init() {}

    func stream() -> AsyncStream<RealtimeEvent> {
        let id = UUID()
        let router = self

        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak router, id] _ in
                Task { @MainActor in
                    router?.removeContinuation(id)
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
