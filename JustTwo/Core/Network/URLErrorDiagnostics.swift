import Foundation

enum URLErrorDiagnostics {

    nonisolated static func summary(for error: Error) -> String {
        if let urlError = error as? URLError {
            return describe(urlError: urlError)
        }

        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else {
            return "\(ns.domain) code=\(ns.code)"
        }

        if let urlError = URLError(_bridgedNSError: ns) {
            return describe(urlError: urlError)
        }

        return "URLError code=\(ns.code) (\(symbolName(for: ns.code)))"
    }

    nonisolated private static func describe(urlError: URLError) -> String {
        var parts = [
            "URLError code=\(urlError.errorCode) (\(symbolName(for: urlError.errorCode)))"
        ]
        if let url = urlError.failingURL {
            parts.append("url=\(url.absoluteString)")
        }
        return parts.joined(separator: " ")
    }

    nonisolated private static func symbolName(for code: Int) -> String {
        switch code {
        case NSURLErrorCancelled:
            return "cancelled"
        case NSURLErrorTimedOut:
            return "timedOut"
        case NSURLErrorCannotFindHost:
            return "cannotFindHost"
        case NSURLErrorCannotConnectToHost:
            return "cannotConnectToHost"
        case NSURLErrorDNSLookupFailed:
            return "dnsLookupFailed"
        case NSURLErrorNotConnectedToInternet:
            return "notConnectedToInternet"
        case NSURLErrorNetworkConnectionLost:
            return "connectionLost"
        case NSURLErrorSecureConnectionFailed:
            return "secureConnectionFailed"
        case NSURLErrorCannotLoadFromNetwork:
            return "cannotLoadFromNetwork"
        default:
            return "unknown"
        }
    }
}
