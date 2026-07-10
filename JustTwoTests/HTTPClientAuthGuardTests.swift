import Foundation
import Testing
@testable import JustTwo

struct HTTPClientAuthGuardTests {

    @Test
    func authenticatedRequestWithoutTokenThrowsUnauthorized() async {
        let previousToken = APIAuth.accessToken
        defer {
            if let previousToken {
                try? APIAuth.save(token: previousToken)
            } else {
                APIAuth.clear()
            }
        }

        APIAuth.clear()

        let client = HTTPClient(
            session: .shared,
            configuration: .current
        )

        do {
            _ = try await client.send(TestAuthenticatedRequest())
            Issue.record("Expected unauthorized error")
        } catch let error as NetworkError {
            if case .unauthorized = error {
                #expect(Bool(true))
            } else {
                Issue.record("Expected unauthorized, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private struct TestAuthenticatedRequest: APIRequest {
    typealias Response = EmptyResponse

    var path: String { "v1/me" }
    var method: HTTPMethod { .get }
    var body: Data? { nil }
    var queryItems: [URLQueryItem] { [] }
    var headers: [String: String] { [:] }
    var requiresAuth: Bool { true }
}
