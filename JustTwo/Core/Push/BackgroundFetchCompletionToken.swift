import UIKit

/// Guarantees a single `UIBackgroundFetchResult` per background push callback.
final class BackgroundFetchCompletionToken: @unchecked Sendable {
    private nonisolated let lock = NSLock()
    private nonisolated(unsafe) var finished = false
    private nonisolated(unsafe) let completion: (UIBackgroundFetchResult) -> Void

    nonisolated init(_ completion: @escaping (UIBackgroundFetchResult) -> Void) {
        self.completion = completion
    }

    nonisolated func finish(_ result: UIBackgroundFetchResult) {
        let shouldComplete: Bool = lock.withLock {
            guard !finished else { return false }
            finished = true
            return true
        }
        guard shouldComplete else {
            MessengerDiagnostics.event(
                .messengerBackgroundCompletionDuplicateIgnored,
                metadata: ["result": fetchResultName(result)]
            )
            return
        }
        MessengerDiagnostics.event(
            .messengerBackgroundCompletionCalled,
            metadata: ["result": fetchResultName(result)]
        )
        completion(result)
    }

    nonisolated var hasFinished: Bool {
        lock.withLock { finished }
    }

    private nonisolated func fetchResultName(_ result: UIBackgroundFetchResult) -> String {
        switch result {
        case .newData: return "newData"
        case .noData: return "noData"
        case .failed: return "failed"
        @unknown default: return "unknown"
        }
    }
}
