import Foundation

enum DeepLink: Equatable {
    case emailVerification(token: String)
    case passwordReset(token: String)
    case invite(token: String)
    case invalidAuthLink(message: String, isPasswordReset: Bool)
}

enum DeepLinkParser {
    private static let supportedHost = "api.jtwo.online"

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme == "https", url.host == supportedHost else { return nil }

        if url.path == "/auth/verify-email" || url.path == "/auth/reset-password" {
            return parseAuthLink(url)
        }

        if url.path.hasPrefix("/invite/") {
            return parseInviteLink(url)
        }

        return nil
    }

    private static func parseAuthLink(_ url: URL) -> DeepLink? {
        guard let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "token" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else {
            return .invalidAuthLink(
                message: missingTokenMessage(for: url.path),
                isPasswordReset: url.path == "/auth/reset-password"
            )
        }

        switch url.path {
        case "/auth/verify-email":
            return .emailVerification(token: token)
        case "/auth/reset-password":
            return .passwordReset(token: token)
        default:
            return nil
        }
    }

    private static func parseInviteLink(_ url: URL) -> DeepLink? {
        guard let token = inviteToken(from: url) else { return nil }
        return .invite(token: token)
    }

    static func inviteToken(from url: URL) -> String? {
        guard url.scheme == "https", url.host == supportedHost, url.path.hasPrefix("/invite/") else {
            return nil
        }

        let rawToken = String(url.path.dropFirst("/invite/".count))
        let decoded = rawToken.removingPercentEncoding ?? rawToken
        let token = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    static func inviteToken(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for candidate in inviteLinkCandidates(from: trimmed) {
            if let token = inviteToken(from: candidate) {
                return token
            }
        }

        return nil
    }

    private static func inviteLinkCandidates(from string: String) -> [URL] {
        var urls: [URL] = []

        if let direct = URL(string: string) {
            urls.append(direct)
        }

        if let prefixed = URL(string: "https://\(string)") {
            urls.append(prefixed)
        }

        let pattern = #"https://api\.jtwo\.online/invite/[^\s]+"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
           let range = Range(match.range, in: string),
           let matched = URL(string: String(string[range])) {
            urls.append(matched)
        }

        return urls
    }

    private static func missingTokenMessage(for path: String) -> String {
        switch path {
        case "/auth/reset-password":
            return String(localized: "reset_password.error.missing_token")
        default:
            return String(localized: "email_verification.error.missing_token")
        }
    }
}
