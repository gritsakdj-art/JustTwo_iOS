import Foundation

@MainActor
enum MessengerBackgroundSessionPreparer {

    /// Bounded session recovery for background push reconciliation.
    /// Restores JWT from Keychain and hydrates a cached snapshot when needed.
    /// Never presents login UI.
    static func prepare(session: SessionStore) async -> MessengerBackgroundSessionContext? {
        do {
            try APIAuth.restorePersistedSession()
        } catch {
            MessengerDiagnostics.event(
                .messengerBackgroundDependenciesUnavailable,
                metadata: ["reason": "tokenRestoreFailed"]
            )
            return nil
        }

        guard APIAuth.accessToken != nil else {
            return nil
        }

        if session.currentUser == nil {
            if let snapshot = await StartupSessionSnapshotStore.shared.load() {
                session.applyStartupSnapshot(snapshot)
            }
        }

        guard session.hasActiveSession else {
            return nil
        }

        guard session.isFullyAuthenticated else {
            MessengerDiagnostics.event(
                .messengerBackgroundPushIgnored,
                metadata: ["reason": "emailNotVerified"]
            )
            return nil
        }

        do {
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            guard let userID = session.currentUser?.id else { return nil }

            ConversationDeliveryAckCoordinator.shared.boundaryStore = MessengerLocalStore.shared
            await MessengerSyncEngine.shared.hydrateFromLocalStore()

            return MessengerBackgroundSessionContext(
                ownerProfileID: profileID,
                userID: userID,
                syncEngineGeneration: MessengerSyncEngine.shared.sessionGenerationForTests,
                ackCoordinatorGeneration: ConversationDeliveryAckCoordinator.shared.sessionGenerationForTests
            )
        } catch {
            MessengerDiagnostics.event(
                .messengerBackgroundSyncFailed,
                metadata: [
                    "reason": "profileResolutionFailed",
                    "errorCategory": MessengerDiagnostics.sanitizeError(error)
                ]
            )
            return nil
        }
    }

    static func isContextStillValid(
        _ context: MessengerBackgroundSessionContext,
        session: SessionStore
    ) -> Bool {
        guard session.currentUser?.id == context.userID else { return false }
        guard session.isFullyAuthenticated else { return false }
        guard session.currentProfile?.id == context.ownerProfileID else { return false }
        guard MessengerSyncEngine.shared.sessionGenerationForTests == context.syncEngineGeneration else { return false }
        guard ConversationDeliveryAckCoordinator.shared.sessionGenerationForTests == context.ackCoordinatorGeneration else {
            return false
        }
        return true
    }
}
