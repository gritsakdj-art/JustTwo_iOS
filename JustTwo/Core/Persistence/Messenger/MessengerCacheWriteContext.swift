import Foundation

struct MessengerCacheWriteContext: Sendable, Equatable {
    let sessionGeneration: Int
    let accountUserID: UUID?

    @MainActor
    static func capture(from store: MessengerLocalStore) -> MessengerCacheWriteContext {
        MessengerCacheWriteContext(
            sessionGeneration: store.currentSessionGeneration,
            accountUserID: SessionStore.shared.currentUser?.id
        )
    }

    @MainActor
    func staleReason(store: MessengerLocalStore) -> String? {
        if store.isResetInFlightPublic {
            return "resetInFlight"
        }
        if sessionGeneration != store.currentSessionGeneration {
            return "staleSession"
        }
        let currentAccountUserID = SessionStore.shared.currentUser?.id
        if accountUserID != currentAccountUserID {
            return "accountMismatch"
        }
        return nil
    }

    @MainActor
    var isValid: Bool {
        staleReason(store: MessengerLocalStore.shared) == nil
    }
}

@MainActor
enum MessengerCacheWriteGuard {

    static func logIgnored(
        reason: String,
        context: MessengerCacheWriteContext,
        source: MessengerConversationCacheSource,
        store: MessengerLocalStore
    ) {
        MessengerDiagnostics.event(
            .presenceCacheWriteIgnored,
            metadata: [
                "reason": reason,
                "source": source.rawValue,
                "capturedSessionGeneration": "\(context.sessionGeneration)",
                "currentSessionGeneration": "\(store.currentSessionGeneration)",
                "hasAccountMismatch": context.accountUserID != SessionStore.shared.currentUser?.id ? "true" : "false"
            ]
        )
    }
}
