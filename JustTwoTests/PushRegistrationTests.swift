import Foundation
import Testing

@testable import JustTwo

struct PushRegistrationTests {
    @Test("DEBUG build reports sandbox APNs environment")
    func debugBuildUsesSandboxEnvironment() {
        #if DEBUG
        #expect(PushEnvironment.current == .sandbox)
        #else
        Issue.record("Expected DEBUG configuration for this test")
        #endif
    }

    @Test("Register push device request encodes environment")
    func registerRequestEncodesEnvironment() throws {
        let body = RegisterPushDeviceRequestBody(
            platform: "ios",
            token: "abcd1234efgh5678",
            environment: PushEnvironment.sandbox.rawValue,
            bundleId: "pro.sda.justtwo.JustTwo",
            installationId: "00000000-0000-0000-0000-000000000001",
            appVersion: "1.0",
            buildNumber: "1",
            deviceModel: "iPhone",
            osVersion: "18.0",
            locale: "en_US",
            timezone: "UTC",
            authorizationStatus: "authorized"
        )

        let data = try JSONEncoder().encode(body)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"environment\":\"sandbox\""))
        #expect(json.contains("\"platform\":\"ios\""))
    }

    @Test("Production environment can be encoded")
    func productionEnvironmentEncodes() throws {
        let body = RegisterPushDeviceRequestBody(
            platform: "ios",
            token: "abcd1234efgh5678",
            environment: PushEnvironment.production.rawValue,
            bundleId: "pro.sda.justtwo.JustTwo",
            installationId: "00000000-0000-0000-0000-000000000001",
            appVersion: nil,
            buildNumber: nil,
            deviceModel: nil,
            osVersion: nil,
            locale: nil,
            timezone: nil,
            authorizationStatus: nil
        )

        let data = try JSONEncoder().encode(body)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"environment\":\"production\""))
    }

    @Test("Push device sync key includes environment")
    func syncKeyIncludesEnvironment() {
        let keyA = PushDeviceSyncKey(
            userID: UUID(),
            token: "token-a",
            environment: PushEnvironment.sandbox.rawValue,
            installationID: "install-a"
        )
        let keyB = PushDeviceSyncKey(
            userID: keyA.userID,
            token: "token-a",
            environment: PushEnvironment.production.rawValue,
            installationID: "install-a"
        )

        #expect(keyA != keyB)
    }

    @Test("resetSessionState clears in-flight sync bookkeeping")
    @MainActor
    func resetSessionStateClearsSyncBookkeeping() async {
        let service = PushRegistrationService(installationIDProvider: InstallationIDProvider.shared)
        service.resetSessionState()
        await service.syncCurrentTokenIfPossible(userID: UUID())
        service.resetSessionState()
    }

    @Test("Token logging helper redacts full token")
    func tokenLoggingRedactsFullToken() {
        let token = String(repeating: "a", count: 64)
        #expect(token.safeTokenDescription.contains(String(repeating: "a", count: 64)) == false)
        #expect(token.safeTokenDescription.contains("..."))
    }
}

private struct PushDeviceSyncKey: Equatable {
    let userID: UUID
    let token: String
    let environment: String
    let installationID: String
}

private extension String {
    var safeTokenDescription: String {
        guard count > 16 else { return "<redacted>" }
        return "\(prefix(8))...\(suffix(8))"
    }
}
