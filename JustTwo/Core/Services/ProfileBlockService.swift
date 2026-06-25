import Foundation

enum ProfileBlockService {
    nonisolated static func blockProfile(profileID: UUID, reason: String? = nil) async throws -> ProfileBlockDTO {
        try await NetworkExecutor.shared.send(BlockProfileRequest(profileID: profileID, reason: reason))
    }
}
