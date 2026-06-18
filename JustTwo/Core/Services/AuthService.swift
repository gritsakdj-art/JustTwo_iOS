import Foundation

enum AuthService {

    static func login(email: String, password: String) async throws -> AuthResponse {
        try await NetworkExecutor.shared.send(
            LoginRequest(email: email, password: password),
            strategies: NetworkStrategy.defaultFlow
        )
    }

    static func register(email: String, password: String) async throws -> AuthResponse {
        try await NetworkExecutor.shared.send(
            RegisterRequest(email: email, password: password),
            strategies: NetworkStrategy.defaultFlow
        )
    }

    static func currentUser() async throws -> UserResponse {
        try await NetworkExecutor.shared.send(CurrentUserRequest())
    }

    static func refreshCurrentUser() async throws -> UserResponse {
        try await currentUser()
    }

    static func resendVerification(email: String) async throws -> MessageResponse {
        try await NetworkExecutor.shared.send(
            ResendVerificationRequest(email: email),
            strategies: NetworkStrategy.defaultFlow
        )
    }

    static func verifyEmail(token: String) async throws -> MessageResponse {
        try await NetworkExecutor.shared.send(
            VerifyEmailRequest(token: token),
            strategies: NetworkStrategy.defaultFlow
        )
    }
}
