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
    nonisolated static let current = APIConfiguration(environment: .staging)

    let environment: APIEnvironment

    nonisolated var baseURL: URL { environment.baseURL }
    nonisolated var realtimeWebSocketURL: URL { environment.realtimeWebSocketURL }
    nonisolated var requestTimeout: TimeInterval { 20 }
    nonisolated var resourceTimeout: TimeInterval { 60 }
}
