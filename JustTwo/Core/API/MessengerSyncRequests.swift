import Foundation

struct GetMessengerSyncStateRequest: APIRequest {
    typealias Response = MessengerSyncStateResponse

    var path: String { "messenger/sync/state" }
    var method: HTTPMethod { .get }
    var requiresAuth: Bool { true }
}

struct GetMessengerSyncEventsRequest: APIRequest {
    typealias Response = MessengerSyncEventsResponse

    let afterRevision: Int64
    let limit: Int
    let conversationID: UUID?

    var path: String { "messenger/sync/events" }
    var method: HTTPMethod { .get }
    var requiresAuth: Bool { true }

    var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "afterRevision", value: String(afterRevision)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let conversationID {
            items.append(URLQueryItem(name: "conversationID", value: conversationID.uuidString))
        }
        return items
    }

    init(
        afterRevision: Int64,
        limit: Int = MessengerSyncLimits.defaultEventPageSize,
        conversationID: UUID? = nil
    ) {
        self.afterRevision = afterRevision
        self.limit = min(max(limit, 1), MessengerSyncLimits.maximumEventPageSize)
        self.conversationID = conversationID
    }
}
