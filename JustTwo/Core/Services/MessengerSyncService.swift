import Foundation

enum MessengerSyncService {

    #if DEBUG
    /// Test hook: when set, bypasses network and returns the handler result.
    nonisolated(unsafe) static var testingFetchSyncEventsHandler: (
        (Int64, UUID?) async throws -> MessengerSyncEventsResponse
    )?
    #endif

    nonisolated static func fetchSyncState() async throws -> MessengerSyncStateResponse {
        try await NetworkExecutor.shared.send(GetMessengerSyncStateRequest())
    }

    nonisolated static func fetchSyncEvents(
        afterRevision: Int64,
        limit: Int = MessengerSyncLimits.defaultEventPageSize,
        conversationID: UUID? = nil
    ) async throws -> MessengerSyncEventsResponse {
        #if DEBUG
        if let testingFetchSyncEventsHandler {
            return try await testingFetchSyncEventsHandler(afterRevision, conversationID)
        }
        #endif
        return try await NetworkExecutor.shared.send(
            GetMessengerSyncEventsRequest(
                afterRevision: afterRevision,
                limit: limit,
                conversationID: conversationID
            )
        )
    }
}
