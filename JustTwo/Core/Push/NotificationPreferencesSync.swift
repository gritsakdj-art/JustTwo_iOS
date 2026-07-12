import Foundation

/// Pushes the locally-configured notification toggles (Profile → General Settings)
/// to the backend `/me/notification-preferences` endpoint so server-side push
/// content (alert vs silent, message preview text) matches the user's choice.
///
/// Without this, the backend keeps its defaults (`messagePreviewEnabled = false`),
/// which is why APNs alerts arrive with generic text while local notifications —
/// built from the local toggle — show the real message body.
@MainActor
final class NotificationPreferencesSync {
    static let shared = NotificationPreferencesSync()

    private init() {}

    private struct Snapshot: Equatable {
        var messagesEnabled: Bool
        var messagePreviewEnabled: Bool
    }

    private var lastSyncedSnapshot: Snapshot?
    private var isSyncing = false
    private var hasPendingResync = false

    /// Sends the current local preferences to the backend. Deduplicates identical
    /// consecutive syncs unless `force` is set.
    func syncFromLocalPreferences(force: Bool = false) {
        Task { @MainActor in
            await performSync(force: force)
        }
    }

    /// Clears the cached synced state so the next sync always hits the network.
    /// Call on logout so a different account re-syncs from scratch.
    func resetSyncedState() {
        lastSyncedSnapshot = nil
    }

    private func performSync(force: Bool) async {
        guard SessionStore.shared.isFullyAuthenticated else { return }

        let snapshot = Snapshot(
            messagesEnabled: MessageNotificationPreferences.messagesEnabled,
            messagePreviewEnabled: MessageNotificationPreferences.messagePreviewEnabled
        )

        if !force, snapshot == lastSyncedSnapshot { return }

        guard !isSyncing else {
            hasPendingResync = true
            return
        }

        isSyncing = true
        defer {
            isSyncing = false
            if hasPendingResync {
                hasPendingResync = false
                Task { @MainActor [weak self] in
                    await self?.performSync(force: false)
                }
            }
        }

        let body = UpdateNotificationPreferencesBody(
            messagesEnabled: snapshot.messagesEnabled,
            messagePreviewEnabled: snapshot.messagePreviewEnabled
        )

        do {
            _ = try await NetworkExecutor.shared.send(
                UpdateNotificationPreferencesRequest(bodyValue: body)
            )
            lastSyncedSnapshot = snapshot
            NetworkDebug.log(
                "Notification preferences synced messages=\(snapshot.messagesEnabled) preview=\(snapshot.messagePreviewEnabled)"
            )
        } catch {
            NetworkDebug.logError(error, prefix: "Notification preferences sync failed")
        }
    }
}
