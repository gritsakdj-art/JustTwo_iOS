import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

protocol APIRequest {
    associatedtype Response: Decodable

    var path: String { get }
    var method: HTTPMethod { get }
    var queryItems: [URLQueryItem] { get }
    var headers: [String: String] { get }
    var body: Data? { get }
    var requiresAuth: Bool { get }
}

extension APIRequest {
    var queryItems: [URLQueryItem] { [] }
    var headers: [String: String] { [:] }
    var body: Data? { nil }
    var requiresAuth: Bool { false }
}

protocol EncodableAPIRequest: APIRequest {
    associatedtype Body: Encodable

    var bodyValue: Body? { get }
}

extension EncodableAPIRequest {
    var body: Data? {
        guard let bodyValue else { return nil }
        return try? JSONCoding.encoder.encode(bodyValue)
    }
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct APIErrorResponse: Decodable {
    let success: Bool
    let code: String
    let message: String
    let field: String?
}

struct HealthResponse: Decodable {
    let status: String
    let service: String
}

struct HealthCheckRequest: APIRequest {
    typealias Response = HealthResponse

    var path: String { "health" }
    var method: HTTPMethod { .get }
}
