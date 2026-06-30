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
        syncPushRegistrationIfEligible()
        PushNotificationRoutingCoordinator.shared.applyPendingRouteIfPossible()
    }

    func setCurrentUser(_ user: UserResponse) {
        currentUser = user
        pendingVerificationEmail = user.emailVerified ? nil : user.email

        if !user.emailVerified {
            currentProfile = nil
            MessengerBadgeStore.shared.reset()
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
        let pushUnregisterToken = APIAuth.accessToken
        Task { @MainActor in
            await PushRegistrationService.shared.unregisterCurrentDevice(accessToken: pushUnregisterToken)
        }

        MessengerRealtimeCoordinator.shared.stop()
        ConversationDeliveryAckCoordinator.shared.reset()
        realtimeClient.disconnect()
        MessengerBadgeStore.shared.reset()

        if let userID = currentUser?.id {
            ProfilePhotoLocalOrderStore.shared.clear(userID: userID)
            ProfileAvatarCropStore.shared.clear(userID: userID)
        }
        APIAuth.clear()
        currentUser = nil
        currentProfile = nil
        pendingVerificationEmail = nil
        PushNotificationRoutingCoordinator.shared.clearPendingRoute()
        AppStartupCoordinator.shared.reset()
        ProfilePhotoStore.shared.reset()
    }

    func signOut() {
        clearSession()
    }

    func connectRealtimeIfEligible() {
        guard isFullyAuthenticated else {
            MessengerBadgeStore.shared.reset()
            realtimeClient.disconnect()
            return
        }

        Task { @MainActor [realtimeClient] in
            await realtimeClient.connectIfPossible()
        }
    }

    func syncPushRegistrationIfEligible() {
        guard isFullyAuthenticated else { return }

        Task { @MainActor in
            await PushRegistrationService.shared.requestAuthorizationIfNeeded()
            await PushRegistrationService.shared.syncCurrentTokenIfPossible(userID: currentUser?.id)
        }
    }

    func applicationDidBecomeActive() {
        guard isFullyAuthenticated else {
            MessengerBadgeStore.shared.reset()
            realtimeClient.disconnect()
            return
        }

        realtimeClient.applicationDidBecomeActive()
        syncPushRegistrationIfEligible()
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
