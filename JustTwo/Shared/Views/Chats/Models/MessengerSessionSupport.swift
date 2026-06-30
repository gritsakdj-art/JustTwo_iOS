import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum MessengerSessionSupport {

    static var isAppForegroundActive: Bool {
        #if canImport(UIKit)
        UIApplication.shared.applicationState == .active
        #else
        true
        #endif
    }

    @MainActor
    static func resolveCurrentProfileID(session: SessionStore) async throws -> UUID {
        if let profileID = session.currentProfile?.id {
            return profileID
        }

        if let profile = try await ProfileService.fetchMyProfile() {
            session.updateCurrentProfile(profile)
            return profile.id
        }

        throw MessengerSessionError.missingProfile
    }

    @MainActor
    static func handleNetworkError(
        _ error: NetworkError,
        session: SessionStore,
        router: AppRouter
    ) -> String? {
        if error.shouldClearSession {
            session.clearSession()
            router.resetTo(.auth)
            return nil
        }
        return error.userMessage
    }
}

enum MessengerSessionError: LocalizedError {
    case missingProfile

    var errorDescription: String? {
        String(localized: "chats.error.missing_profile")
    }
}
