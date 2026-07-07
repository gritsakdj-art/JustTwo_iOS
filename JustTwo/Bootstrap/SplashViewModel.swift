import Foundation

@MainActor
@Observable
final class SplashViewModel {

    private(set) var state: SplashState = .loading
    private(set) var phase: Phase = .restoringSession

    private let session: SessionStore
    private let router: AppRouter
    private let snapshotStore: StartupSessionSnapshotStoreProtocol
    private var didStart = false
    private var flowToken = UUID()
    private var flowTask: Task<Void, Never>?
    private var networkWatchID: UUID?

    private enum Timing {
        static let minimumDisplayDuration: Duration = .milliseconds(900)
    }

    init(
        session: SessionStore,
        router: AppRouter,
        snapshotStore: StartupSessionSnapshotStoreProtocol? = nil
    ) {
        self.session = session
        self.router = router
        self.snapshotStore = snapshotStore ?? StartupSessionSnapshotStore.shared
    }

    func onAppear() {
        guard !didStart else { return }
        didStart = true
        start()
    }

    func retry() {
        stopNetworkWatch()
        didStart = false
        start(force: true)
    }

    func cancel() {
        stopNetworkWatch()
        flowTask?.cancel()
        flowTask = nil
    }

    func errorSubtitle(for error: NetworkError) -> String {
        switch error {
        case .noInternet:
            return String(localized: "splash.error.no_internet")
        case .tlsFailure:
            return String(localized: "splash.error.tls")
        case .timeout:
            return String(localized: "splash.error.timeout")
        case .connectionLost:
            return String(localized: "splash.error.connection_lost")
        case .serverUnavailable:
            return String(localized: "splash.error.server_unavailable")
        case .unauthorized:
            return String(localized: "splash.error.unauthorized")
        case .cancelled:
            return String(localized: "splash.error.cancelled")
        case .httpError, .decodingError, .invalidResponse, .unknown:
            return error.userMessage
        }
    }

    private func start(force: Bool = false) {
        if !force, flowTask != nil { return }
        cancel()

        let token = UUID()
        flowToken = token
        state = .loading
        phase = .restoringSession
        didStart = true

        flowTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runFlow(token: token)
            if self.flowToken == token {
                self.flowTask = nil
            }
        }
    }

    private func runFlow(token: UUID) async {
        func setState(_ newState: SplashState) {
            guard flowToken == token else { return }
            state = newState

            if case .result = newState {
                router.handleSplash(newState)
            }
        }

        func setPhase(_ newPhase: Phase) {
            guard flowToken == token else { return }
            phase = newPhase
            NetworkDebug.log("Splash phase → \(newPhase.logLabel)")
        }

        let startedAt = ContinuousClock.now
        NetworkDebug.log("Splash flow started")

        do {
            setState(.loading)
            setPhase(.restoringSession)

            try APIAuth.restorePersistedSession()
            guard flowToken == token else { return }

            guard let accessToken = APIAuth.accessToken else {
                MessengerDiagnostics.event(.splashTokenMissing)
                session.clearSession()
                await ensureMinimumDisplayDuration(since: startedAt, token: token)
                guard flowToken == token else { return }
                logFlowFinished(since: startedAt, result: "needAuth")
                MessengerDiagnostics.event(.splashRouteAuth)
                setState(.result(.needAuth))
                return
            }

            MessengerDiagnostics.event(.splashTokenFound)

            if JWTPayloadReader.isExpired(token: accessToken) == true {
                MessengerDiagnostics.event(.splashTokenExpiredLocal)
                session.clearSession()
                await ensureMinimumDisplayDuration(since: startedAt, token: token)
                guard flowToken == token else { return }
                MessengerDiagnostics.event(.splashRouteAuth)
                setState(.result(.needAuth))
                return
            }

            let cachedSnapshot = await snapshotStore.load()
            if let cachedSnapshot {
                session.applyStartupSnapshot(cachedSnapshot)
            }

            setPhase(.loadingUser)
            MessengerDiagnostics.event(
                .splashNetworkValidationStarted,
                metadata: [
                    "hasCachedUser": cachedSnapshot == nil ? "false" : "true",
                    "hasCachedProfile": cachedSnapshot?.profile == nil ? "false" : "true"
                ]
            )

            let validation = await performNetworkValidation(session: session, hadUsableCache: cachedSnapshot?.isUsableForOfflineMain == true)
            guard flowToken == token else { return }

            if case .recoverableFailure = validation,
               cachedSnapshot?.isUsableForOfflineMain != true {
                let error = session.lastValidationError ?? .noInternet
                setState(.networkError(error))
                beginNetworkWatchForAutoRetry(token: token)
                return
            }

            let route = SplashRouteResolver.resolve(
                hasToken: true,
                isTokenLocallyExpired: false,
                cachedSnapshot: cachedSnapshot,
                validation: validation
            )

            switch route {
            case .needAuth:
                session.clearSession()
                stopNetworkWatch()
                await ensureMinimumDisplayDuration(since: startedAt, token: token)
                guard flowToken == token else { return }
                MessengerDiagnostics.event(.splashRouteAuth)
                setState(.result(.needAuth))
                return

            case .needEmailVerification(let email):
                stopNetworkWatch()
                await ensureMinimumDisplayDuration(since: startedAt, token: token)
                guard flowToken == token else { return }
                setState(.result(.needEmailVerification(email: email)))
                return

            case .needProfileSetup:
                stopNetworkWatch()
                await ensureMinimumDisplayDuration(since: startedAt, token: token)
                guard flowToken == token else { return }
                MessengerDiagnostics.event(.splashRouteProfileSetup)
                setState(.result(.needProfileSetup))
                return

            case .recoverableOfflineError:
                MessengerDiagnostics.event(.splashOfflineCachedSessionRejected)
                setState(.offlineRecoverable)
                beginNetworkWatchForAutoRetry(token: token)
                return

            case .readyFromNetwork:
                setPhase(.loadingProfile)
                session.markOnlineValidated()
                MessengerDiagnostics.event(.splashRouteMainFromNetwork)
                MessengerDiagnostics.event(.splashNetworkValidationSucceeded)

            case .readyFromCache:
                session.markOfflineUsingCache()
                MessengerDiagnostics.event(.splashOfflineCachedSessionAccepted)
                MessengerDiagnostics.event(.splashRouteMainFromCache)
                MessengerDiagnostics.event(
                    .splashNetworkValidationFailedRecoverable,
                    metadata: ["route": "cachedSession"]
                )
            }

            setPhase(.loadingChats)
            await AppStartupWarmupStore.shared.warmupAuthenticatedHome(
                session: session,
                router: router
            )
            guard flowToken == token else { return }

            if route == .readyFromNetwork {
                session.connectRealtimeIfEligible()
                session.syncPushRegistrationIfEligible()
            } else if route == .readyFromCache {
                StartupSessionValidationService.shared.beginWatching(session: session, router: router)
            }

            stopNetworkWatch()
            await ensureMinimumDisplayDuration(since: startedAt, token: token)
            guard flowToken == token else { return }
            logFlowFinished(since: startedAt, result: "ready")
            setState(.result(.ready))
        } catch is CancellationError {
            return
        } catch let error as NetworkError where error.shouldClearSession {
            NetworkDebug.logError(error)
            session.clearSession()
            stopNetworkWatch()
            await ensureMinimumDisplayDuration(since: startedAt, token: token)
            guard flowToken == token else { return }
            MessengerDiagnostics.event(
                .splashNetworkValidationFailedAuth,
                metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
            )
            setState(.result(.needAuth))
        } catch let error as NetworkError {
            NetworkDebug.log("Splash flow failed phase=\(phase.logLabel) error=\(error)")
            NetworkDebug.logError(error, prefix: "Splash")
            setState(.networkError(error))
            beginNetworkWatchForAutoRetry(token: token)
        } catch {
            let mapped = NetworkError.map(error)
            NetworkDebug.log("Splash flow failed phase=\(phase.logLabel) error=\(mapped)")
            NetworkDebug.logError(error, prefix: "Splash")
            setState(.networkError(mapped))
            beginNetworkWatchForAutoRetry(token: token)
        }
    }

    private func performNetworkValidation(
        session: SessionStore,
        hadUsableCache: Bool
    ) async -> SplashNetworkValidationResult {
        if hadUsableCache, !NetworkPathMonitor.shared.isNetworkSatisfied {
            return .offlineAccepted
        }

        do {
            let user = try await AuthService.currentUser(
                strategies: SplashStartupPolicy.authStrategies,
                configuration: .splash
            )
            session.setCurrentUser(user)
            await snapshotStore.save(user: user, profile: session.currentProfile)

            guard user.emailVerified else {
                return .needsEmailVerification(email: user.email)
            }

            let profile = try await ProfileStartupLoader.shared.loadIfNeeded(
                session: session,
                strategies: SplashStartupPolicy.authStrategies,
                configuration: .splash
            )

            return .success(hasProfile: profile != nil)
        } catch let error as NetworkError where error.shouldClearSession {
            MessengerDiagnostics.event(
                .splashNetworkValidationFailedAuth,
                metadata: ["errorCategory": MessengerDiagnostics.sanitizeError(error)]
            )
            return .authFailure
        } catch let error as NetworkError where error.isRecoverableForOfflineStartup {
            if hadUsableCache {
                return .offlineAccepted
            }
            if session.currentUser != nil, session.currentProfile == nil {
                session.markValidationFailedRecoverable(lastError: error)
                return .offlineRejectedNoProfile
            }
            session.markValidationFailedRecoverable(lastError: error)
            return .recoverableFailure
        } catch {
            let mapped = NetworkError.map(error)
            if mapped.isRecoverableForOfflineStartup {
                if hadUsableCache {
                    return .offlineAccepted
                }
                if session.currentUser != nil, session.currentProfile == nil {
                    session.markValidationFailedRecoverable(lastError: mapped)
                    return .offlineRejectedNoProfile
                }
                session.markValidationFailedRecoverable(lastError: mapped)
            }
            return .recoverableFailure
        }
    }

    private func beginNetworkWatchForAutoRetry(token: UUID) {
        stopNetworkWatch()
        networkWatchID = NetworkPathMonitor.shared.registerPathChangeHandler { [weak self] in
            guard let self, self.flowToken == token else { return }
            switch self.state {
            case .networkError, .offlineRecoverable:
                NetworkDebug.log("Splash auto-retry: network path changed")
                self.retry()
            default:
                break
            }
        }
    }

    private func stopNetworkWatch() {
        if let networkWatchID {
            NetworkPathMonitor.shared.unregisterHandler(networkWatchID)
            self.networkWatchID = nil
        }
    }

    private func ensureMinimumDisplayDuration(
        since startedAt: ContinuousClock.Instant,
        token: UUID
    ) async {
        let elapsed = startedAt.duration(to: .now)
        let remaining = Timing.minimumDisplayDuration - elapsed

        guard remaining > .zero else { return }

        try? await Task.sleep(for: remaining)
        guard flowToken == token else { return }
    }

    private func logFlowFinished(since startedAt: ContinuousClock.Instant, result: String) {
        let elapsed = startedAt.duration(to: .now)
        let milliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        NetworkDebug.log(
            "Splash flow finished result=\(result) in \(String(format: "%.0f", milliseconds))ms"
        )
    }
}

extension SplashViewModel {

    enum Phase: Equatable {
        case restoringSession
        case loadingUser
        case loadingProfile
        case loadingChats
        case finishing

        var title: LocalizedStringResource {
            switch self {
            case .restoringSession:
                return "splash.phase.restoring_session"
            case .loadingUser:
                return "splash.phase.loading_user"
            case .loadingProfile:
                return "splash.phase.loading_profile"
            case .loadingChats:
                return "splash.phase.loading_chats"
            case .finishing:
                return "splash.phase.finishing"
            }
        }

        var logLabel: String {
            switch self {
            case .restoringSession:
                return "restoringSession"
            case .loadingUser:
                return "loadingUser"
            case .loadingProfile:
                return "loadingProfile"
            case .loadingChats:
                return "loadingChats"
            case .finishing:
                return "finishing"
            }
        }
    }
}
