import Foundation

@MainActor
@Observable
final class SessionStore {

    static let shared = SessionStore()

    private(set) var currentUser: UserResponse?
    private(set) var currentProfile: UserProfileDTO?
    private(set) var pendingVerificationEmail: String?

    var isEmailVerified: Bool {
        currentUser?.emailVerified == true
    }

    var hasActiveSession: Bool {
        APIAuth.accessToken != nil
    }

    var isFullyAuthenticated: Bool {
        hasActiveSession && isEmailVerified
    }

    private init() {}

    func signIn(_ response: AuthResponse) throws {
        guard let token = response.token, let user = response.user else {
            throw AuthSessionError.missingTokenOrUser
        }

        try APIAuth.save(token: token)
        currentUser = user
        currentProfile = nil
        pendingVerificationEmail = user.emailVerified ? nil : user.email
    }

    func setCurrentUser(_ user: UserResponse) {
        currentUser = user
        pendingVerificationEmail = user.emailVerified ? nil : user.email

        if !user.emailVerified {
            currentProfile = nil
        }
    }

    func updateCurrentProfile(_ profile: UserProfileDTO?) {
        currentProfile = profile
    }

    func setPendingVerificationEmail(_ email: String?) {
        pendingVerificationEmail = email
    }

    func clearSession() {
        if let userID = currentUser?.id {
            ProfilePhotoLocalOrderStore.shared.clear(userID: userID)
            ProfileAvatarCropStore.shared.clear(userID: userID)
        }
        APIAuth.clear()
        currentUser = nil
        currentProfile = nil
        pendingVerificationEmail = nil
        ProfilePhotoStore.shared.reset()
    }

    func signOut() {
        clearSession()
    }
}

enum AuthSessionError: LocalizedError {
    case missingTokenOrUser

    var errorDescription: String? {
        String(localized: "auth.error.missing_session_payload")
    }
}
