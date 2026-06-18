import Foundation

@MainActor
@Observable
final class SessionStore {

    static let shared = SessionStore()

    enum Phase: Equatable {
        case loading
        case auth
        case profileSetup
        case main
        case sessionRecoveryFailed
    }

    private(set) var phase: Phase = .loading
    private(set) var currentUser: UserResponse?
    private(set) var currentProfile: UserProfileDTO?
    private(set) var recoveryErrorMessage: String?

    private init() {}

    func bootstrap() async {
        do {
            try APIAuth.restorePersistedSession()
        } catch {
            NetworkDebug.logError(error, prefix: "keychain")
            APIAuth.clear()
            phase = .auth
            return
        }

        guard APIAuth.accessToken != nil else {
            phase = .auth
            return
        }

        await resolveDestinationAfterAuth()
    }

    func handleAuthSuccess(_ response: AuthResponse, isRegistration: Bool) async throws {
        try APIAuth.save(token: response.token)
        currentUser = response.user
        recoveryErrorMessage = nil

        if isRegistration {
            currentProfile = nil
            phase = .profileSetup
            return
        }

        await resolveDestinationAfterAuth()
    }

    func updateCurrentProfile(_ profile: UserProfileDTO) {
        currentProfile = profile
        if phase == .profileSetup {
            phase = .main
        }
    }

    func signOut() {
        APIAuth.clear()
        currentUser = nil
        currentProfile = nil
        recoveryErrorMessage = nil
        phase = .auth
    }

    private func resolveDestinationAfterAuth() async {
        phase = .loading

        do {
            currentUser = try await AuthService.currentUser()

            let profile = try await ProfileService.fetchMyProfile()
            currentProfile = profile
            recoveryErrorMessage = nil
            phase = profile == nil ? .profileSetup : .main
        } catch let error as NetworkError where error.shouldClearSession {
            NetworkDebug.logError(error)
            APIAuth.clear()
            currentUser = nil
            currentProfile = nil
            recoveryErrorMessage = nil
            phase = .auth
        } catch {
            NetworkDebug.logError(error)
            recoveryErrorMessage = NetworkError.map(error).userMessage
            phase = .sessionRecoveryFailed
        }
    }
}
