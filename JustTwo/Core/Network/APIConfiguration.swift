import Foundation

enum APIEnvironment: Sendable {
    case staging
    case production

    var baseURL: URL {
        switch self {
        case .staging, .production:
            return URL(string: "https://api.jtwo.online")!
        }
    }
}

struct APIConfiguration: Sendable {
    static var current = APIConfiguration(environment: .staging)

    let environment: APIEnvironment

    var baseURL: URL { environment.baseURL }
    var requestTimeout: TimeInterval { 20 }
    var resourceTimeout: TimeInterval { 60 }
}
