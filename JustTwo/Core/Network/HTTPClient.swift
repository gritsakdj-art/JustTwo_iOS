import Foundation

struct HTTPClient: Sendable {

    let session: URLSession
    let configuration: APIConfiguration

    func send<R: APIRequest>(_ request: R) async throws -> R.Response where R.Response: Decodable {
        let urlRequest = try makeURLRequest(for: request)
        NetworkDebug.log("➡️ \(urlRequest.httpMethod ?? "GET") \(redactedURLDescription(urlRequest.url, fallback: request.path))")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        NetworkDebug.log("⬅️ status=\(httpResponse.statusCode) bytes=\(data.count)")

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try JSONCoding.decoder.decode(R.Response.self, from: data)
            } catch {
                NetworkDebug.logError(error, prefix: "decode")
                throw NetworkError.decodingError(error.localizedDescription)
            }

        case 401:
            let apiError = try? JSONCoding.decoder.decode(APIErrorResponse.self, from: data)
            if let apiError {
                throw NetworkError.httpError(statusCode: 401, response: apiError)
            }
            throw NetworkError.unauthorized

        default:
            let apiError = try? JSONCoding.decoder.decode(APIErrorResponse.self, from: data)
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, response: apiError)
        }
    }

    private func makeURLRequest<R: APIRequest>(for request: R) throws -> URLRequest {
        let url = request.path
            .split(separator: "/")
            .map(String.init)
            .reduce(configuration.baseURL) { partialResult, component in
                partialResult.appendingPathComponent(component)
            }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidResponse
        }

        if !request.queryItems.isEmpty {
            components.queryItems = request.queryItems
        }

        guard let url = components.url else {
            throw NetworkError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body

        var headers = defaultHeaders()
        request.headers.forEach { headers[$0.key] = $0.value }

        if request.requiresAuth, let token = APIAuth.accessToken {
            headers["Authorization"] = "Bearer \(token)"
        }

        headers.forEach { urlRequest.setValue($0.value, forHTTPHeaderField: $0.key) }
        return urlRequest
    }

    private func defaultHeaders() -> [String: String] {
        [
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
    }

    private func redactedURLDescription(_ url: URL?, fallback: String) -> String {
        guard let url else { return fallback }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return fallback
        }

        components.queryItems = components.queryItems?.map { item in
            guard item.name.lowercased() == "token" else { return item }
            return URLQueryItem(name: item.name, value: "<redacted>")
        }

        return components.url?.absoluteString ?? fallback
    }
}
