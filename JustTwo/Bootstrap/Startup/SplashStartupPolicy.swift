import Foundation

enum SplashStartupPolicy {
    /// Fast-fail strategies for splash auth (`/me`, `/profile/me`).
    /// Two short attempts instead of the full 4-strategy ~74s cycle.
    nonisolated static let authStrategies: [NetworkStrategy] = NetworkStrategy.splashFlow
}
