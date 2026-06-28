import Foundation

@MainActor
@Observable
final class SessionStore {

    static let shared = SessionStore()

    private(set) var currentUser: UserResponse?
    private(set) var currentProfile: UserProfileDTO?
    private(set) var pendingVerificationEmail: String?
    let realtimeClient = RealtimeClient.shared

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

        connectRealtimeIfEligible()
    }

    func setCurrentUser(_ user: UserResponse) {
        currentUser = user
        pendingVerificationEmail = user.emailVerified ? nil : user.email

        if !user.emailVerified {
            currentProfile = nil
            realtimeClient.disconnect()
        }
    }

    func updateCurrentProfile(_ profile: UserProfileDTO?) {
        currentProfile = profile
    }

    func setPendingVerificationEmail(_ email: String?) {
        pendingVerificationEmail = email
    }

    func clearSession() {
        realtimeClient.disconnect()

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

    func connectRealtimeIfEligible() {
        guard isFullyAuthenticated else {
            realtimeClient.disconnect()
            return
        }

        Task { @MainActor [realtimeClient] in
            await realtimeClient.connectIfPossible()
        }
    }

    func applicationDidBecomeActive() {
        guard isFullyAuthenticated else {
            realtimeClient.disconnect()
            return
        }

        realtimeClient.applicationDidBecomeActive()
    }

    func applicationDidEnterBackground() {
        realtimeClient.applicationDidEnterBackground()
    }
}

enum AuthSessionError: LocalizedError {
    case missingTokenOrUser

    var errorDescription: String? {
        String(localized: "auth.error.missing_session_payload")
    }
}
