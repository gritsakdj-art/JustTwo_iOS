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
        didStart = false
        start(force: true)
    }

    func cancel() {
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
        }

        let startedAt = ContinuousClock.now

        do {
            setState(.loading)
            setPhase(.restoringSession)

            try APIAuth.restorePersistedSession()
            guard flowToken == token else { return }

            guard APIAuth.accessToken != nil else {
                session.clearSession()
                await ensureMinimumDisplayDuration(since: startedAt, token: token)
                guard flowToken == token else { return }
                setState(.result(.needAuth))
                return
            }

            setPhase(.loadingUser)
            let user = try await AuthService.currentUser()
            session.setCurrentUser(user)
            guard flowToken == token else { return }

            guard user.emailVerified else {
                await ensureMinimumDisplayDuration(since: startedAt, token: token)
                guard flowToken == token else { return }
                setState(.result(.needEmailVerification(email: user.email)))
                return
            }

            setPhase(.loadingProfile)
            let profile = try await ProfileStartupLoader.shared.loadIfNeeded(session: session)
            guard flowToken == token else { return }

            setPhase(.finishing)
            if profile != nil {
                session.connectRealtimeIfEligible()
                await AppStartupWarmupStore.shared.warmupAuthenticatedHome(
                    session: session,
                    router: router
                )
            }
            guard flowToken == token else { return }

            await ensureMinimumDisplayDuration(since: startedAt, token: token)
            guard flowToken == token else { return }
            setState(.result(profile == nil ? .needProfileSetup : .ready))
        } catch is CancellationError {
            return
        } catch let error as NetworkError where error.shouldClearSession {
            NetworkDebug.logError(error)
            session.clearSession()
            await ensureMinimumDisplayDuration(since: startedAt, token: token)
            guard flowToken == token else { return }
            setState(.result(.needAuth))
        } catch let error as NetworkError {
            setState(.networkError(error))
        } catch {
            setState(.networkError(NetworkError.map(error)))
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
}

extension SplashViewModel {

    enum Phase: Equatable {
        case restoringSession
        case loadingUser
        case loadingProfile
        case finishing

        var title: LocalizedStringResource {
            switch self {
            case .restoringSession:
                return "splash.phase.restoring_session"
            case .loadingUser:
                return "splash.phase.loading_user"
            case .loadingProfile:
                return "splash.phase.loading_profile"
            case .finishing:
                return "splash.phase.finishing"
            }
        }
    }
}
