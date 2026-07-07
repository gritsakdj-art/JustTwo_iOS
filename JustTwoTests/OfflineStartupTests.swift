import Foundation
import Testing
@testable import JustTwo

@Suite(.serialized)
@MainActor
struct OfflineStartupTests {

    @Test
    func snapshotStoreSavesAndLoadsUserProfile() async throws {
        let store = makeTestSnapshotStore()
        let user = makeTestUser()
        let profile = makeTestProfile()

        await store.save(user: user, profile: profile)
        let loaded = await store.load()

        #expect(loaded?.userID == user.id)
        #expect(loaded?.user.email == user.email)
        #expect(loaded?.profile?.id == profile.id)
        #expect(loaded?.isUsableForOfflineMain == true)
    }

    @Test
    func snapshotStoreClearsOnLogoutReset() async throws {
        let store = makeTestSnapshotStore()
        await store.save(user: makeTestUser(), profile: makeTestProfile())
        await store.clear()

        #expect(await store.load() == nil)
    }

    @Test
    func snapshotDoesNotStoreJWT() async throws {
        let store = makeTestSnapshotStore()
        await store.save(user: makeTestUser(), profile: makeTestProfile())

        let url = StartupSessionSnapshotStore.testingFileURL!
        let raw = try String(contentsOf: url, encoding: .utf8).lowercased()

        #expect(!raw.contains("bearer"))
        #expect(!raw.contains("authorization"))
        #expect(!raw.contains("eyj"))
    }

    @Test
    func snapshotDoesNotStoreSignedURLs() async throws {
        let store = makeTestSnapshotStore()
        await store.save(user: makeTestUser(), profile: makeTestProfile())

        let url = StartupSessionSnapshotStore.testingFileURL!
        let raw = try String(contentsOf: url, encoding: .utf8).lowercased()

        #expect(!raw.contains("downloadurl"))
        #expect(!raw.contains("uploadurl"))
        #expect(!raw.contains("x-amz-signature"))
    }

    @Test
    func splashRouteResolverNoTokenRoutesAuth() {
        let route = SplashRouteResolver.resolve(
            hasToken: false,
            isTokenLocallyExpired: false,
            cachedSnapshot: nil,
            validation: .recoverableFailure
        )

        #expect(route == .needAuth)
    }

    @Test
    func splashRouteResolverExpiredTokenRoutesAuth() {
        let route = SplashRouteResolver.resolve(
            hasToken: true,
            isTokenLocallyExpired: true,
            cachedSnapshot: makeSnapshot(),
            validation: .offlineAccepted
        )

        #expect(route == .needAuth)
    }

    @Test
    func splashRouteResolverAuthFailureRoutesAuth() {
        let route = SplashRouteResolver.resolve(
            hasToken: true,
            isTokenLocallyExpired: false,
            cachedSnapshot: makeSnapshot(),
            validation: .authFailure
        )

        #expect(route == .needAuth)
    }

    @Test
    func splashRouteResolverProfileNotFoundRoutesSetup() {
        let route = SplashRouteResolver.resolve(
            hasToken: true,
            isTokenLocallyExpired: false,
            cachedSnapshot: nil,
            validation: .success(hasProfile: false)
        )

        #expect(route == .needProfileSetup)
    }

    @Test
    func splashRouteResolverOfflineWithCacheRoutesMain() {
        let snapshot = makeSnapshot()
        let route = SplashRouteResolver.resolve(
            hasToken: true,
            isTokenLocallyExpired: false,
            cachedSnapshot: snapshot,
            validation: .offlineAccepted
        )

        #expect(route == .readyFromCache)
    }

    @Test
    func splashRouteResolverOfflineWithoutProfileShowsRecoverableState() {
        let route = SplashRouteResolver.resolve(
            hasToken: true,
            isTokenLocallyExpired: false,
            cachedSnapshot: nil,
            validation: .offlineRejectedNoProfile
        )

        #expect(route == .recoverableOfflineError)
    }

    @Test
    func splashRouteResolverNetworkSuccessRoutesMain() {
        let route = SplashRouteResolver.resolve(
            hasToken: true,
            isTokenLocallyExpired: false,
            cachedSnapshot: nil,
            validation: .success(hasProfile: true)
        )

        #expect(route == .readyFromNetwork)
    }

    @Test
    func splashRouteResolverEmailVerificationGate() {
        let route = SplashRouteResolver.resolve(
            hasToken: true,
            isTokenLocallyExpired: false,
            cachedSnapshot: makeSnapshot(),
            validation: .needsEmailVerification(email: "user@example.com")
        )

        #expect(route == .needEmailVerification(email: "user@example.com"))
    }

    @Test
    func splashRouteResolverRecoverableFailureWithoutSnapshotShowsRecoverableError() {
        let route = SplashRouteResolver.resolve(
            hasToken: true,
            isTokenLocallyExpired: false,
            cachedSnapshot: nil,
            validation: .recoverableFailure
        )

        #expect(route == .recoverableOfflineError)
    }

    @Test
    func splashRouteResolverRecoverableFailureWithUsableCacheRoutesMain() {
        let route = SplashRouteResolver.resolve(
            hasToken: true,
            isTokenLocallyExpired: false,
            cachedSnapshot: makeSnapshot(),
            validation: .recoverableFailure
        )

        #expect(route == .readyFromCache)
    }

    @Test
    func sessionStoreMarksOfflineUsingCache() {
        let session = SessionStore.shared
        session.applyStartupSnapshot(makeSnapshot())

        #expect(session.connectivityState == .offlineUsingCache)
        #expect(session.shouldShowOfflineBanner == true)
        #expect(session.currentProfile != nil)
    }

    @Test
    func sessionStoreClearsOfflineStateOnOnlineValidation() {
        let session = SessionStore.shared
        session.applyStartupSnapshot(makeSnapshot())
        session.markOnlineValidated()

        #expect(session.connectivityState == .online)
        #expect(session.shouldShowOfflineBanner == false)
    }

    @Test
    func criticalLocalWarmupDoesNotRequireNetwork() async {
        let coordinator = AppStartupCoordinator.shared
        await coordinator.reset()

        let session = SessionStore.shared
        session.applyStartupSnapshot(makeSnapshot())

        await coordinator.runCriticalLocalWarmup(session: session, router: AppRouter.shared)

        #expect(coordinator.warmedUserID == session.currentUser?.id)
        #expect(coordinator.isRunningCritical == false)
    }

    @Test
    func logoutResetClearsStartupSnapshot() async throws {
        let coordinator = AppStartupCoordinator.shared
        let store = makeTestSnapshotStore()
        await store.save(user: makeTestUser(), profile: makeTestProfile())

        await coordinator.reset()

        #expect(await store.load() == nil)
    }

    @Test
    func networkErrorRecoverableDoesNotClearSession() {
        #expect(NetworkError.noInternet.isRecoverableForOfflineStartup == true)
        #expect(NetworkError.noInternet.shouldClearSession == false)
        #expect(NetworkError.unauthorized.shouldClearSession == true)
        #expect(NetworkError.unauthorized.isRecoverableForOfflineStartup == false)
    }
}

private func makeTestSnapshotStore() -> StartupSessionSnapshotStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("startup-snapshot-\(UUID().uuidString).json")
    StartupSessionSnapshotStore.testingFileURL = url
    return StartupSessionSnapshotStore.shared
}

private func makeTestUser() -> UserResponse {
    UserResponse(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        email: "user@example.com",
        emailVerified: true
    )
}

private func makeTestProfile() -> UserProfileDTO {
    UserProfileDTO(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        displayName: "Test User",
        birthDate: "1990-01-01",
        gender: "woman",
        moodModeEnabled: true,
        activityModeEnabled: true
    )
}

private func makeSnapshot() -> StartupSessionSnapshot {
    StartupSessionSnapshotMapping.snapshot(user: makeTestUser(), profile: makeTestProfile())
}
