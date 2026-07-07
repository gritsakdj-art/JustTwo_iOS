import Foundation

enum APIEnvironment: Sendable {
    case staging
    case production

    nonisolated var baseURL: URL {
        switch self {
        case .staging, .production:
            return URL(string: "https://api.jtwo.online")!
        }
    }

    nonisolated var realtimeWebSocketURL: URL {
        switch self {
        case .staging, .production:
            return URL(string: "wss://api.jtwo.online/ws/realtime")!
        }
    }
}

struct APIConfiguration: Sendable {
    nonisolated static let current = APIConfiguration(
        environment: .staging,
        requestTimeout: 20,
        resourceTimeout: 60,
        operationTimeout: 30
    )

    nonisolated static let splash = APIConfiguration(
        environment: .staging,
        requestTimeout: 10,
        resourceTimeout: 15,
        operationTimeout: 15
    )

    let environment: APIEnvironment
    let requestTimeout: TimeInterval
    let resourceTimeout: TimeInterval
    let operationTimeout: TimeInterval

    nonisolated var baseURL: URL { environment.baseURL }
    nonisolated var realtimeWebSocketURL: URL { environment.realtimeWebSocketURL }
}
