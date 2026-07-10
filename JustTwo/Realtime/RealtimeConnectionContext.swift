import Foundation

struct RealtimeConnectionContext: Sendable, Equatable {
    let connectionID: UUID
    let connectionEpoch: Int
    let sessionGeneration: Int
}

struct RealtimeRoutedEvent: Sendable {
    let event: RealtimeEvent
    let context: RealtimeConnectionContext
}

@MainActor
enum RealtimeTransportGuard {

    private(set) static var activeConnectionID: UUID?
    private(set) static var activeConnectionEpoch: Int = 0

    /// Called when a new `URLSessionWebSocketTask` receive cycle begins.
    static func beginConnection(presenceStore: PresenceStore) -> RealtimeConnectionContext {
        presenceStore.beginRealtimeReconnectCycle()
        let connectionID = UUID()
        activeConnectionID = connectionID
        activeConnectionEpoch = presenceStore.currentRealtimeConnectionEpoch
        return RealtimeConnectionContext(
            connectionID: connectionID,
            connectionEpoch: activeConnectionEpoch,
            sessionGeneration: presenceStore.currentSessionGeneration
        )
    }

    static func invalidateActiveConnection() {
        activeConnectionID = nil
    }

    static func accepts(
        _ context: RealtimeConnectionContext,
        presenceStore: PresenceStore
    ) -> Bool {
        staleReason(for: context, presenceStore: presenceStore) == nil
    }

    static func staleReason(
        for context: RealtimeConnectionContext,
        presenceStore: PresenceStore
    ) -> String? {
        if context.sessionGeneration != presenceStore.currentSessionGeneration {
            return "staleSessionGeneration"
        }
        if context.connectionEpoch != presenceStore.currentRealtimeConnectionEpoch {
            return "staleConnectionEpoch"
        }
        if context.connectionID != activeConnectionID {
            return "staleConnectionID"
        }
        return nil
    }

    static func logIgnoredEvent(
        _ event: RealtimeEvent,
        context: RealtimeConnectionContext,
        presenceStore: PresenceStore
    ) {
        let reason = staleReason(for: context, presenceStore: presenceStore) ?? "staleTransport"
        var metadata: [String: String] = [
            "reason": reason,
            "eventType": event.type,
            "capturedEpoch": "\(context.connectionEpoch)",
            "currentEpoch": "\(presenceStore.currentRealtimeConnectionEpoch)",
            "capturedSessionGeneration": "\(context.sessionGeneration)",
            "currentSessionGeneration": "\(presenceStore.currentSessionGeneration)",
            "hasAccountMismatch": "false"
        ]
        if let profileID = presenceProfileID(for: event) {
            metadata["profileID"] = MessengerDiagnostics.sanitizeID(profileID)
        }
        MessengerDiagnostics.event(.realtimeTransportEpochIgnored, metadata: metadata)
    }

    #if DEBUG
    static func resetForTesting() {
        activeConnectionID = nil
        activeConnectionEpoch = 0
    }

    static func setActiveConnectionForTesting(
        connectionID: UUID,
        connectionEpoch: Int
    ) {
        activeConnectionID = connectionID
        activeConnectionEpoch = connectionEpoch
    }
    #endif

    private static func presenceProfileID(for event: RealtimeEvent) -> UUID? {
        guard case .presenceChanged(let payload) = event else { return nil }
        return payload.profileID
    }
}
