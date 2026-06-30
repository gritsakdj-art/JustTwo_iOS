import Foundation

@MainActor
@Observable
final class SplashViewModel {

    private(set) var state: SplashState = .loading
    private(set) var phase: Phase = .restoringSession

    private let session: SessionStore
    private let router: AppRouter
    private var didStart = false
    private var flowToken = UUID()
    private var flowTask: Task<Void, Never>?
    private var networkWatchID: UUID?

    private enum Timing {
        static let minimumDisplayDuration: Duration = .milliseconds(900)
    }

    init(session: SessionStore, router: AppRouter) {
        self.session = session
        self.router = router
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

            guard APIAuth.accessToken != nil else {
                session.clearSession()
                await ensureMinimumDisplayDuration(since: startedAt, token: token)
                guard flowToken == token else { return }
                logFlowFinished(since: startedAt, result: "needAuth")
                setState(.result(.needAuth))
                return
            }

            setPhase(.loadingUser)
            let user = try await AuthService.currentUser(
                strategies: SplashStartupPolicy.authStrategies,
                configuration: .splash
            )
            session.setCurrentUser(user)
            guard flowToken == token else { return }

            guard user.emailVerified else {
                await ensureMinimumDisplayDuration(since: startedAt, token: token)
                guard flowToken == token else { return }
                logFlowFinished(since: startedAt, result: "needEmailVerification")
                setState(.result(.needEmailVerification(email: user.email)))
                return
            }

            setPhase(.loadingProfile)
            let profile = try await ProfileStartupLoader.shared.loadIfNeeded(
                session: session,
                strategies: SplashStartupPolicy.authStrategies,
                configuration: .splash
            )
            guard flowToken == token else { return }

            if profile != nil {
                setPhase(.loadingChats)
                session.connectRealtimeIfEligible()
                session.syncPushRegistrationIfEligible()
                await AppStartupWarmupStore.shared.warmupAuthenticatedHome(
                    session: session,
                    router: router
                )
            }
            guard flowToken == token else { return }

            stopNetworkWatch()
            await ensureMinimumDisplayDuration(since: startedAt, token: token)
            guard flowToken == token else { return }
            let result: SplashResult = profile == nil ? .needProfileSetup : .ready
            logFlowFinished(since: startedAt, result: String(describing: result))
            setState(.result(result))
        } catch is CancellationError {
            return
        } catch let error as NetworkError where error.shouldClearSession {
            NetworkDebug.logError(error)
            session.clearSession()
            stopNetworkWatch()
            await ensureMinimumDisplayDuration(since: startedAt, token: token)
            guard flowToken == token else { return }
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

    private func beginNetworkWatchForAutoRetry(token: UUID) {
        stopNetworkWatch()
        networkWatchID = NetworkPathMonitor.shared.registerPathChangeHandler { [weak self] in
            guard let self, self.flowToken == token else { return }
            guard case .networkError = self.state else { return }
            NetworkDebug.log("Splash auto-retry: network path changed")
            self.retry()
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
