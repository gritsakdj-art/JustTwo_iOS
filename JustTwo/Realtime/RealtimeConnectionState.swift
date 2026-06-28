import Foundation

enum RealtimeConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected(connectionID: UUID?)
    case reconnecting(attempt: Int)
    case failed(message: String)
}
