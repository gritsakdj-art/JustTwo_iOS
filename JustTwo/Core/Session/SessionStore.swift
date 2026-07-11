import Foundation

enum SessionConnectivityState: Equatable, Sendable {
    case online
    case offlineUsingCache
    case validationPending
    case validationFailedRecoverable
}

@MainActor
@Observable
final class SessionStore {

    static let shared = SessionStore()

    private(set) var currentUser: UserResponse?
    private(set) var currentProfile: UserProfileDTO?
    private(set) var pendingVerificationEmail: String?
    private(set) var connectivityState: SessionConnectivityState = .online
    private(set) var lastValidationError: NetworkError?
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

    var shouldShowOfflineBanner: Bool {
        connectivityState == .offlineUsingCache || connectivityState == .validationPending
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
        connectivityState = .online
        lastValidationError = nil

        Task {
            await StartupSessionSnapshotStore.shared.save(user: user, profile: nil)
        }

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

    func applyStartupSnapshot(_ snapshot: StartupSessionSnapshot) {
        currentUser = StartupSessionSnapshotMapping.userResponse(from: snapshot.user)
        pendingVerificationEmail = snapshot.user.emailVerified ? nil : snapshot.user.email
        currentProfile = snapshot.profile.map(StartupSessionSnapshotMapping.userProfile(from:))
        markOfflineUsingCache()
    }

    func updateCurrentProfile(_ profile: UserProfileDTO?) {
        currentProfile = profile
    }

    func markOnlineValidated() {
        connectivityState = .online
        lastValidationError = nil
        StartupSessionValidationService.shared.stopWatching()
    }

    func markValidationPending() {
        connectivityState = .validationPending
    }

    func markOfflineUsingCache(lastError: NetworkError? = nil) {
        connectivityState = .offlineUsingCache
        lastValidationError = lastError
    }

    func markValidationFailedRecoverable(lastError: NetworkError? = nil) {
        connectivityState = .validationFailedRecoverable
        lastValidationError = lastError
    }

    func setPendingVerificationEmail(_ email: String?) {
        pendingVerificationEmail = email
    }

    func clearSession() {
        StartupSessionValidationService.shared.stopWatching()

        let pushUnregisterToken = APIAuth.accessToken
        let loggingOutUserID = currentUser?.id
        Task { @MainActor in
            await PushRegistrationService.shared.unregisterCurrentDevice(accessToken: pushUnregisterToken)
        }
        PushRegistrationService.shared.resetSessionState()

        MessengerRealtimeCoordinator.shared.stop()
        ConversationDeliveryAckCoordinator.shared.reset()
        realtimeClient.disconnect()
        MessengerBadgeStore.shared.reset()

        if let userID = loggingOutUserID {
            ProfilePhotoLocalOrderStore.shared.clear(userID: userID)
            ProfileAvatarCropStore.shared.clear(userID: userID)
        }
        APIAuth.clear()
        currentUser = nil
        currentProfile = nil
        pendingVerificationEmail = nil
        connectivityState = .online
        lastValidationError = nil
        PushNotificationRoutingCoordinator.shared.clearPendingRoute()
        AppStartupCoordinator.shared.scheduleLogoutReset()
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

        let sessionUserID = currentUser?.id
        Task { @MainActor [realtimeClient, weak self] in
            guard let self,
                  self.isFullyAuthenticated,
                  self.currentUser?.id == sessionUserID else {
                return
            }
            await realtimeClient.connectIfPossible()
        }
    }

    func syncPushRegistrationIfEligible() {
        guard isFullyAuthenticated else { return }

        let sessionUserID = currentUser?.id
        Task { @MainActor [weak self] in
            guard let self,
                  self.isFullyAuthenticated,
                  self.currentUser?.id == sessionUserID else {
                return
            }
            await PushRegistrationService.shared.requestAuthorizationIfNeeded()
            guard self.isFullyAuthenticated,
                  self.currentUser?.id == sessionUserID else {
                return
            }
            await PushRegistrationService.shared.syncCurrentTokenIfPossible(userID: sessionUserID)
        }
    }

    func applicationDidBecomeActive() {
        guard isFullyAuthenticated else {
            MessengerBadgeStore.shared.reset()
            realtimeClient.disconnect()
            return
        }

        let sessionUserID = currentUser?.id
        realtimeClient.applicationDidBecomeActive()
        ConversationDeliveryAckCoordinator.shared.retryPendingAcks(reason: "appForeground")
        syncPushRegistrationIfEligible()

        Task { @MainActor [weak self] in
            guard let self,
                  self.isFullyAuthenticated,
                  self.currentUser?.id == sessionUserID else {
                return
            }
            await MessengerSyncEngine.shared.runGlobalSync(
                reason: .appForeground,
                session: self,
                router: AppRouter.shared
            )
        }
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
