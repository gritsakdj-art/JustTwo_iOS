import Foundation

nonisolated struct NotificationPreferencesPayload: Decodable, Sendable {
    let messagesEnabled: Bool
    let reactionsEnabled: Bool
    let connectionsEnabled: Bool
    let messagePreviewEnabled: Bool
    let soundEnabled: Bool
    let badgeEnabled: Bool
    let quietHoursEnabled: Bool
    let quietHoursStart: String?
    let quietHoursEnd: String?
}

nonisolated struct NotificationPreferencesEnvelope: Decodable, Sendable {
    let success: Bool
    let preferences: NotificationPreferencesPayload
}

struct UpdateNotificationPreferencesBody: Encodable {
    var messagesEnabled: Bool?
    var reactionsEnabled: Bool?
    var connectionsEnabled: Bool?
    var messagePreviewEnabled: Bool?
    var soundEnabled: Bool?
    var badgeEnabled: Bool?
    var quietHoursEnabled: Bool?
    var quietHoursStart: String?
    var quietHoursEnd: String?
}

struct FetchNotificationPreferencesRequest: APIRequest {
    typealias Response = NotificationPreferencesEnvelope

    var path: String { "me/notification-preferences" }
    var method: HTTPMethod { .get }
    var requiresAuth: Bool { true }
}

struct UpdateNotificationPreferencesRequest: EncodableAPIRequest {
    typealias Response = NotificationPreferencesEnvelope
    typealias Body = UpdateNotificationPreferencesBody

    let bodyValue: UpdateNotificationPreferencesBody?

    var path: String { "me/notification-preferences" }
    var method: HTTPMethod { .put }
    var requiresAuth: Bool { true }
}
