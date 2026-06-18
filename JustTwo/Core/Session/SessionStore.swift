import Foundation

@MainActor
@Observable
final class SessionStore {

    static let shared = SessionStore()

    private(set) var currentUser: UserResponse?
    private(set) var currentProfile: UserProfileDTO?

    private init() {}

    func signIn(_ response: AuthResponse) throws {
        try APIAuth.save(token: response.token)
        currentUser = response.user
    }

    func setCurrentUser(_ user: UserResponse) {
        currentUser = user
    }

    func updateCurrentProfile(_ profile: UserProfileDTO?) {
        currentProfile = profile
    }

    func clearSession() {
        APIAuth.clear()
        currentUser = nil
        currentProfile = nil
    }

    func signOut() {
        clearSession()
    }
}
