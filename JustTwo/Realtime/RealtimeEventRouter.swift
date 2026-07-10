import Foundation

@MainActor
@Observable
final class RealtimeEventRouter {

    static let shared = RealtimeEventRouter()

    private var continuations: [UUID: AsyncStream<RealtimeRoutedEvent>.Continuation] = [:]
    private(set) var lastEventType: String?

    private init() {}

    static func makeForTesting() -> RealtimeEventRouter {
        RealtimeEventRouter()
    }

    func stream() -> AsyncStream<RealtimeRoutedEvent> {
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

    func route(_ event: RealtimeEvent, context: RealtimeConnectionContext) {
        lastEventType = event.type
        NetworkDebug.log("Realtime event received: \(event.type)")

        let routed = RealtimeRoutedEvent(event: event, context: context)
        for continuation in continuations.values {
            continuation.yield(routed)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}
