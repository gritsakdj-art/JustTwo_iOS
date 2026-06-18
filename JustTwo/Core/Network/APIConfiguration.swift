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
}

struct APIConfiguration: Sendable {
    nonisolated static let current = APIConfiguration(environment: .staging)

    let environment: APIEnvironment

    nonisolated var baseURL: URL { environment.baseURL }
    nonisolated var requestTimeout: TimeInterval { 20 }
    nonisolated var resourceTimeout: TimeInterval { 60 }
}
