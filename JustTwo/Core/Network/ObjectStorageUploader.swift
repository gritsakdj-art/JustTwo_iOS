import Foundation

enum ObjectStorageUploader {

    enum UploadError: LocalizedError {
        case invalidURL
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return String(localized: "profile.photos.error.upload_failed")
            case .httpStatus(let code):
                return String(localized: "profile.photos.error.upload_failed") + " (\(code))"
            }
        }
    }

    private static let uploadSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    /// Uploads directly to the presigned Object Storage URL.
    /// Uses only the headers returned by backend. Does not use API base URL or JWT Authorization.
    static func upload(
        data: Data,
        uploadURL: String,
        method: String,
        headers: [String: String]
    ) async throws {
        guard let url = URL(string: uploadURL) else {
            throw UploadError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = data

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        NetworkDebug.log("➡️ \(method) \(redactedObjectStorageURL(uploadURL)) bytes=\(data.count)")

        let (_, response) = try await uploadSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        NetworkDebug.log("⬅️ object storage status=\(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            throw UploadError.httpStatus(httpResponse.statusCode)
        }
    }

    private static func redactedObjectStorageURL(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return "<object-storage-url>"
        }

        if var queryItems = components.queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems.map {
                URLQueryItem(name: $0.name, value: "<redacted>")
            }
        } else if components.query != nil {
            components.query = "<redacted>"
        }

        return components.url?.absoluteString ?? "<object-storage-url>"
    }
}
