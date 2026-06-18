import Foundation

enum AppScreen: Hashable {
    case splash
    case auth
    case checkEmail(email: String, message: String?)
    case emailVerificationResult(token: String)
    case emailVerificationError(message: String)
    case profileSetup
    case main
}
