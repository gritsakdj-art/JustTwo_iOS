import Foundation

@MainActor
@Observable
final class AppRouter {

    static let shared = AppRouter()

    var screen: AppScreen = .splash
    var splashError: NetworkError?
    var reloadID = UUID()

    private init() {}

    func goTo(_ screen: AppScreen) {
        self.screen = screen
    }

    func resetTo(_ screen: AppScreen) {
        self.screen = screen
        splashError = nil
    }

    func handleSplash(_ state: SplashState) {
        switch state {
        case .loading:
            break

        case .networkError(let error):
            splashError = error
            screen = .splash

        case .result(let result):
            splashError = nil

            switch result {
            case .needAuth:
                resetTo(.auth)
            case .needEmailVerification(let email):
                showCheckEmail(email: email)
            case .needProfileSetup:
                resetTo(.profileSetup)
            case .ready:
                resetTo(.main)
            }
        }
    }

    func retrySplash() {
        splashError = nil
        reloadID = UUID()
        screen = .splash
    }

    func showCheckEmail(email: String, message: String? = nil) {
        resetTo(.checkEmail(email: email, message: message))
    }

    func showEmailVerificationResult(token: String) {
        resetTo(.emailVerificationResult(token: token))
    }

    func showEmailVerificationError(_ message: String) {
        resetTo(.emailVerificationError(message: message))
    }
}
