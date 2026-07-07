import Foundation

enum SplashNetworkValidationResult: Equatable {
    case success(hasProfile: Bool)
    case offlineAccepted
    case offlineRejectedNoProfile
    case authFailure
    case needsEmailVerification(email: String)
    case recoverableFailure
}

enum SplashRouteDecision: Equatable {
    case needAuth
    case needEmailVerification(email: String)
    case needProfileSetup
    case readyFromNetwork
    case readyFromCache
    case recoverableOfflineError
}

enum SplashRouteResolver {

    static func resolve(
        hasToken: Bool,
        isTokenLocallyExpired: Bool,
        cachedSnapshot: StartupSessionSnapshot?,
        validation: SplashNetworkValidationResult
    ) -> SplashRouteDecision {
        guard hasToken else { return .needAuth }
        if isTokenLocallyExpired { return .needAuth }

        switch validation {
        case .authFailure:
            return .needAuth
        case .needsEmailVerification(let email):
            return .needEmailVerification(email: email)
        case .success(let hasProfile):
            return hasProfile ? .readyFromNetwork : .needProfileSetup
        case .offlineAccepted:
            return cachedSnapshot?.isUsableForOfflineMain == true ? .readyFromCache : .recoverableOfflineError
        case .offlineRejectedNoProfile:
            return .recoverableOfflineError
        case .recoverableFailure:
            if cachedSnapshot?.isUsableForOfflineMain == true {
                return .readyFromCache
            }
            return .recoverableOfflineError
        }
    }
}
