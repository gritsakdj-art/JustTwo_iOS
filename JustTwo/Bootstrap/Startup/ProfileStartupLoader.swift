import Foundation

@MainActor
final class ProfileStartupLoader {

    static let shared = ProfileStartupLoader()

    private var loadTask: Task<UserProfileDTO?, Error>?
    private var loadedForUserID: UUID?

    private init() {}

    func loadIfNeeded(session: SessionStore, force: Bool = false) async throws -> UserProfileDTO? {
        guard let userID = session.currentUser?.id else { return nil }

        if !force, loadedForUserID == userID {
            return session.currentProfile
        }

        if let loadTask, !force {
            return try await loadTask.value
        }

        if force {
            loadTask?.cancel()
            loadTask = nil
            loadedForUserID = nil
        }

        let task = Task { @MainActor () throws -> UserProfileDTO? in
            let profile = try await ProfileService.fetchMyProfile()
            session.updateCurrentProfile(profile)
            return profile
        }
        loadTask = task

        do {
            let profile = try await task.value
            if loadTask == task {
                loadTask = nil
                loadedForUserID = userID
            }
            return profile
        } catch {
            if loadTask == task {
                loadTask = nil
            }
            throw error
        }
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        loadedForUserID = nil
    }
}
