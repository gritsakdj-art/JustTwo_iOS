import Foundation

enum SplashState {
    case loading
    case result(SplashResult)
    case networkError(NetworkError)
}

enum SplashResult: Equatable {
    case needAuth
    case needProfileSetup
    case ready
}
