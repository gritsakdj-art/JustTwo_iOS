import Foundation

enum NetworkRetryPolicy {

    static func shouldRetry(_ error: Error) -> Bool {
        let ns = error as NSError

        guard ns.domain == NSURLErrorDomain else { return false }

        switch ns.code {
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorTimedOut,
             NSURLErrorCancelled:
            return true
        default:
            return false
        }
    }
}
