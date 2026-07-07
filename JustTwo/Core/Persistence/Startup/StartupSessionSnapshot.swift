import Foundation

nonisolated struct StartupUserSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let email: String
    let emailVerified: Bool
    let emailVerifiedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
}

nonisolated struct StartupProfileSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let birthDate: String
    let gender: String
    let bio: String?
    let city: String?
    let latitude: Double?
    let longitude: Double?
    let moodModeEnabled: Bool
    let activityModeEnabled: Bool
    let isVisibleInDiscovery: Bool
    let createdAt: Date?
    let updatedAt: Date?
}

nonisolated struct StartupSessionSnapshot: Codable, Equatable, Sendable {
    let userID: UUID
    let user: StartupUserSnapshot
    let profile: StartupProfileSnapshot?
    let updatedAt: Date

    var isUsableForOfflineMain: Bool {
        user.emailVerified && profile != nil
    }
}

nonisolated enum StartupSessionSnapshotMapping {

    static func userSnapshot(from user: UserResponse) -> StartupUserSnapshot {
        StartupUserSnapshot(
            id: user.id,
            email: user.email,
            emailVerified: user.emailVerified,
            emailVerifiedAt: user.emailVerifiedAt,
            createdAt: user.createdAt,
            updatedAt: user.updatedAt
        )
    }

    static func profileSnapshot(from profile: UserProfileDTO) -> StartupProfileSnapshot {
        StartupProfileSnapshot(
            id: profile.id,
            displayName: profile.displayName,
            birthDate: profile.birthDate,
            gender: profile.gender,
            bio: profile.bio,
            city: profile.city,
            latitude: profile.latitude,
            longitude: profile.longitude,
            moodModeEnabled: profile.moodModeEnabled,
            activityModeEnabled: profile.activityModeEnabled,
            isVisibleInDiscovery: profile.isVisibleInDiscovery,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt
        )
    }

    static func userResponse(from snapshot: StartupUserSnapshot) -> UserResponse {
        UserResponse(
            id: snapshot.id,
            email: snapshot.email,
            emailVerified: snapshot.emailVerified,
            emailVerifiedAt: snapshot.emailVerifiedAt,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
    }

    static func userProfile(from snapshot: StartupProfileSnapshot) -> UserProfileDTO {
        UserProfileDTO(
            id: snapshot.id,
            displayName: snapshot.displayName,
            birthDate: snapshot.birthDate,
            gender: snapshot.gender,
            bio: snapshot.bio,
            city: snapshot.city,
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            moodModeEnabled: snapshot.moodModeEnabled,
            activityModeEnabled: snapshot.activityModeEnabled,
            isVisibleInDiscovery: snapshot.isVisibleInDiscovery,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
    }

    static func snapshot(
        user: UserResponse,
        profile: UserProfileDTO?,
        updatedAt: Date = Date()
    ) -> StartupSessionSnapshot {
        let mappedProfile: StartupProfileSnapshot?
        if let profile {
            mappedProfile = profileSnapshot(from: profile)
        } else {
            mappedProfile = nil
        }

        return StartupSessionSnapshot(
            userID: user.id,
            user: userSnapshot(from: user),
            profile: mappedProfile,
            updatedAt: updatedAt
        )
    }
}
