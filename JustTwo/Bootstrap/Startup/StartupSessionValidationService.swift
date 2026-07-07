import Foundation

@MainActor
final class StartupSessionValidationService {

    static let shared = StartupSessionValidationService()

    private var validationTask: Task<Void, Never>?
    private var networkWatchID: UUID?

    private init() {}

    func beginWatching(session: SessionStore, router: AppRouter) {
        scheduleValidation(session: session, router: router)

        guard networkWatchID == nil else { return }
        networkWatchID = NetworkPathMonitor.shared.registerPathChangeHandler { [weak self] in
            guard let self else { return }
            self.scheduleValidation(session: session, router: router)
        }
    }

    func stopWatching() {
        validationTask?.cancel()
        validationTask = nil

        if let networkWatchID {
            NetworkPathMonitor.shared.unregisterHandler(networkWatchID)
            self.networkWatchID = nil
        }
    }

    func scheduleValidation(session: SessionStore, router: AppRouter, force: Bool = false) {
        guard session.hasActiveSession else {
            stopWatching()
            return
        }

        guard force || session.connectivityState != .online else { return }

        if validationTask != nil, !force {
            return
        }

        validationTask?.cancel()
        validationTask = Task { @MainActor [weak self] in
            await self?.validate(session: session, router: router)
            self?.validationTask = nil
        }
    }

    private func validate(session: SessionStore, router: AppRouter) async {
        guard !Task.isCancelled else { return }
        guard session.hasActiveSession else { return }

        session.markValidationPending()
        MessengerDiagnostics.event(.splashNetworkValidationStarted, metadata: ["source": "background"])

        do {
            let user = try await AuthService.currentUser()
            session.setCurrentUser(user)

            guard user.emailVerified else {
                stopWatching()
                router.showCheckEmail(email: user.email)
                return
            }

            let profile = try await ProfileStartupLoader.shared.loadIfNeeded(session: session)
            await StartupSessionSnapshotStore.shared.save(user: user, profile: profile)

            if profile == nil {
                session.markValidationFailedRecoverable()
                router.resetTo(.profileSetup)
                return
            }

            session.markOnlineValidated()
            session.connectRealtimeIfEligible()
            session.syncPushRegistrationIfEligible()

            await AppStartupCoordinator.shared.runBackgroundNetworkWarmup(
                session: session,
                router: router
            )

            MessengerDiagnostics.event(
                .splashNetworkValidationSucceeded,
                metadata: ["source": "background"]
            )
        } catch let error as NetworkError where error.shouldClearSession {
            MessengerDiagnostics.event(
                .splashNetworkValidationFailedAuth,
                metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
            )
            stopWatching()
            session.clearSession()
            router.resetTo(.auth)
        } catch let error as NetworkError where error.isRecoverableForOfflineStartup {
            MessengerDiagnostics.event(
                .splashNetworkValidationFailedRecoverable,
                metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
            )
            session.markOfflineUsingCache(lastError: error)
        } catch {
            let mapped = NetworkError.map(error)
            if mapped.isRecoverableForOfflineStartup {
                session.markOfflineUsingCache(lastError: mapped)
            } else {
                session.markValidationFailedRecoverable(lastError: mapped)
            }
        }
    }
}
