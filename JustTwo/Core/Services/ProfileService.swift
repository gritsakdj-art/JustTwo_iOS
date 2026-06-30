import Foundation

enum ProfileService {

    static func fetchMyProfile(
        strategies: [NetworkStrategy] = NetworkStrategy.defaultFlow,
        configuration: APIConfiguration = .current
    ) async throws -> UserProfileDTO? {
        do {
            let response = try await NetworkExecutor.shared.send(
                GetProfileRequest(),
                strategies: strategies,
                configuration: configuration
            )
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
