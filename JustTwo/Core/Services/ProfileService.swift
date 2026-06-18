import Foundation

enum ProfileService {

    static func fetchMyProfile() async throws -> UserProfileDTO? {
        do {
            let response = try await NetworkExecutor.shared.send(GetProfileRequest())
            return response.profile
        } catch let error as NetworkError where error.isProfileNotFound {
            return nil
        }
    }

    static func upsertProfile(_ body: UpsertProfileRequestBody) async throws -> UserProfileDTO {
        let response = try await NetworkExecutor.shared.send(UpsertProfileRequest(body: body))
        return response.profile
    }
}
