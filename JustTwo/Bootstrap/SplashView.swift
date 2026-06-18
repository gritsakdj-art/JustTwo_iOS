import SwiftUI

struct SplashView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var viewModel: SplashViewModel?

    var body: some View {
        ZStack {
            Color.discoverBackgroundGradient.ignoresSafeArea()

            if let routerError = router.splashError {
                StatePlaceholderView(
                    title: routerError.userMessage,
                    subtitle: subtitle(for: routerError),
                    systemImage: routerError.systemImage,
                    actionTitle: actionTitle(for: routerError)
                ) {
                    if routerError.isUnauthorized {
                        session.clearSession()
                        router.resetTo(.auth)
                    } else {
                        router.retrySplash()
                    }
                }
            } else if let viewModel {
                switch viewModel.state {
                case .networkError(let error):
                    StatePlaceholderView(
                        title: error.userMessage,
                        subtitle: viewModel.errorSubtitle(for: error),
                        systemImage: error.systemImage,
                        actionTitle: actionTitle(for: error)
                    ) {
                        if error.isUnauthorized {
                            session.clearSession()
                            router.resetTo(.auth)
                        } else {
                            viewModel.retry()
                        }
                    }

                default:
                    JustTwoLoaderCard(
                        title: viewModel.phase.title,
                        subtitle: "splash.subtitle"
                    )
                    .animation(.easeInOut(duration: 0.2), value: viewModel.phase)
                }
            } else {
                JustTwoLoaderCard(
                    title: "splash.phase.restoring_session",
                    subtitle: "splash.subtitle"
                )
            }
        }
        .onAppear(perform: startIfNeeded)
        .onDisappear {
            viewModel?.cancel()
        }
    }

    private func startIfNeeded() {
        if viewModel == nil {
            viewModel = SplashViewModel(session: session, router: router)
        }
        viewModel?.onAppear()
    }

    private func subtitle(for error: NetworkError) -> String {
        viewModel?.errorSubtitle(for: error) ?? error.userMessage
    }

    private func actionTitle(for error: NetworkError) -> LocalizedStringResource? {
        if error.isUnauthorized {
            return "auth.login"
        }

        switch error {
        case .noInternet, .tlsFailure, .timeout, .connectionLost, .serverUnavailable, .httpError:
            return "common.retry"
        case .cancelled, .unauthorized, .decodingError, .invalidResponse, .unknown:
            return nil
        }
    }
}

#Preview {
    SplashView()
        .environment(AppRouter.shared)
        .environment(SessionStore.shared)
}