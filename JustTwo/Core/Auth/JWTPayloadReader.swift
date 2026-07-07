import Foundation

enum JWTPayloadReader {

    /// Returns `true` when token `exp` is in the past, `false` when still valid, `nil` when exp cannot be parsed safely.
    static func isExpired(token: String, now: Date = Date()) -> Bool? {
        guard let payload = decodePayload(token),
              let expiration = payload["exp"] else {
            return nil
        }

        let expirationDate: Date?
        switch expiration {
        case let value as TimeInterval:
            expirationDate = Date(timeIntervalSince1970: value)
        case let value as Int:
            expirationDate = Date(timeIntervalSince1970: TimeInterval(value))
        case let value as String:
            if let interval = TimeInterval(value) {
                expirationDate = Date(timeIntervalSince1970: interval)
            } else {
                expirationDate = nil
            }
        default:
            expirationDate = nil
        }

        guard let expirationDate else { return nil }
        return now >= expirationDate
    }

    private static func decodePayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }

        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else {
            return nil
        }

        return payload
    }
}
