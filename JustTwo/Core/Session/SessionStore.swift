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
    }

    private(set) var phase: Phase = .loading
    private(set) var currentUser: UserResponse?
    private(set) var currentProfile: UserProfileDTO?

    private init() {}

    func bootstrap() async {
        APIAuth.restorePersistedSession()

        guard APIAuth.accessToken != nil else {
            phase = .auth
            return
        }

        await resolveDestinationAfterAuth()
    }

    func handleAuthSuccess(_ response: AuthResponse, isRegistration: Bool) async {
        APIAuth.accessToken = response.token
        APIAuth.persist(user: response.user)
        currentUser = response.user

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
        phase = .auth
    }

    private func resolveDestinationAfterAuth() async {
        phase = .loading

        do {
            if let user = try? await AuthService.currentUser() {
                currentUser = user
            } else if let email = APIAuth.persistedUserEmail, let id = APIAuth.persistedUserID {
                currentUser = UserResponse(id: id, email: email, createdAt: nil, updatedAt: nil)
            }

            let profile = try await ProfileService.fetchMyProfile()
            currentProfile = profile
            phase = profile == nil ? .profileSetup : .main
        } catch {
            NetworkDebug.logError(error)
            APIAuth.clear()
            currentUser = nil
            currentProfile = nil
            phase = .auth
        }
    }
}
