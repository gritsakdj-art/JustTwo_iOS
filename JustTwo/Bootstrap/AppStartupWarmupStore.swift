import Foundation

@MainActor
@Observable
final class AppStartupWarmupStore {

    static let shared = AppStartupWarmupStore()

    private let coordinator = AppStartupCoordinator.shared

    private init() {}

    var isWarmingUp: Bool {
        coordinator.isRunningCritical
    }

    var warmedUserID: UUID? {
        coordinator.warmedUserID
    }

    func warmupAuthenticatedHome(session: SessionStore, router: AppRouter, force: Bool = false) async {
        await coordinator.runCriticalWarmup(session: session, router: router, force: force)
    }

    func reset() {
        coordinator.reset()
    }
}
