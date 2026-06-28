import Foundation

struct RealtimeReconnectPolicy: Equatable, Sendable {
    let initialDelay: TimeInterval
    let multiplier: Double
    let maxDelay: TimeInterval

    nonisolated static let `default` = RealtimeReconnectPolicy(
        initialDelay: 1,
        multiplier: 2,
        maxDelay: 15
    )

    func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return initialDelay }

        let exponential = initialDelay * pow(multiplier, Double(max(0, attempt - 1)))
        return min(exponential, maxDelay)
    }
}
