import Foundation

struct BlockProfileRequestBody: Encodable, Sendable {
    let reason: String?
}

struct ProfileBlockDTO: Decodable, Identifiable, Sendable {
    let id: UUID
    let blockedProfileID: UUID
    let reason: String?
    let createdAt: Date?
}

struct BlockProfileRequest: EncodableAPIRequest {
    typealias Response = ProfileBlockDTO
    typealias Body = BlockProfileRequestBody

    let profileID: UUID
    let bodyValue: BlockProfileRequestBody?

    var path: String { "profiles/\(profileID.uuidString)/block" }
    var method: HTTPMethod { .post }
    var requiresAuth: Bool { true }

    init(profileID: UUID, reason: String? = nil) {
        self.profileID = profileID
        bodyValue = BlockProfileRequestBody(reason: reason)
    }
}
