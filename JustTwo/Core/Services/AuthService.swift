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
}
