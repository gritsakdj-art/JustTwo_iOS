import Foundation

enum MessengerSyncService {

    nonisolated static func fetchSyncState() async throws -> MessengerSyncStateResponse {
        try await NetworkExecutor.shared.send(GetMessengerSyncStateRequest())
    }

    nonisolated static func fetchSyncEvents(
        afterRevision: Int64,
        limit: Int = MessengerSyncLimits.defaultEventPageSize,
        conversationID: UUID? = nil
    ) async throws -> MessengerSyncEventsResponse {
        try await NetworkExecutor.shared.send(
            GetMessengerSyncEventsRequest(
                afterRevision: afterRevision,
                limit: limit,
                conversationID: conversationID
            )
        )
    }
}
