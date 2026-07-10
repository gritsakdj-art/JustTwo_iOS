import Foundation
import UIKit
import UserNotifications

@MainActor
protocol PushRegistrationServicing {
    func configure()
    func requestAuthorizationIfNeeded() async
    func registerForRemoteNotifications()
    func handleDidRegister(deviceToken: Data)
    func handleDidFailToRegister(error: Error)
    func syncCurrentTokenIfPossible() async
    func syncCurrentTokenIfPossible(userID: UUID?) async
    func unregisterCurrentDevice() async
    func unregisterCurrentDevice(accessToken: String?) async
    func resetSessionState()
}

enum PushEnvironment: String, Codable {
    case sandbox
    case production

    static var current: PushEnvironment {
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }
}

@MainActor
final class PushRegistrationService: NSObject, PushRegistrationServicing {
    var onNotificationTap: (([AnyHashable: Any]) -> Void)? {
        didSet {
            deliverPendingNotificationTapIfNeeded()
        }
    }

    private var pendingNotificationTapUserInfo: [AnyHashable: Any]?

    private let center = UNUserNotificationCenter.current()
    private let installationIDProvider: InstallationIDProviding
    private var currentToken: String?
    private var inFlightSyncKey: PushDeviceSyncKey?
    private var lastSuccessfulSyncKey: PushDeviceSyncKey?
    private var pendingSyncUserID: UUID?
    private var sessionGeneration = 0

    init(installationIDProvider: InstallationIDProviding) {
        self.installationIDProvider = installationIDProvider
    }

    private static func makeShared() -> PushRegistrationService {
        PushRegistrationService(installationIDProvider: InstallationIDProvider.shared)
    }

    static let shared = makeShared()

    func configure() {
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        var status = settings.authorizationStatus

        if status == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                status = await center.notificationSettings().authorizationStatus
            } catch {
                NetworkDebug.logError(error, prefix: "Push notification authorization failed")
                return
            }
        }

        guard status.allowsAPNsRegistration else {
            NetworkDebug.log("Push notifications permission unavailable: \(status.pushString)")
            return
        }

        registerForRemoteNotifications()
    }

    func registerForRemoteNotifications() {
        if Thread.isMainThread {
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func handleDidRegister(deviceToken: Data) {
        let token = deviceToken.lowercaseHexString
        currentToken = token
        NetworkDebug.log(
            "APNs token received environment=\(PushEnvironment.current.rawValue) \(token.safeTokenDescription)"
        )

        Task { @MainActor [weak self] in
            let sessionUserID = SessionStore.shared.currentUser?.id
            guard SessionStore.shared.isFullyAuthenticated,
                  SessionStore.shared.currentUser?.id == sessionUserID else {
                return
            }
            await self?.syncCurrentTokenIfPossible(userID: sessionUserID)
        }
    }

    func handleDidFailToRegister(error: Error) {
        NetworkDebug.logError(error, prefix: "APNs registration failed")
    }

    func syncCurrentTokenIfPossible() async {
        await syncCurrentTokenIfPossible(userID: SessionStore.shared.currentUser?.id)
    }

    func syncCurrentTokenIfPossible(userID: UUID?) async {
        let syncSessionGeneration = sessionGeneration
        guard APIAuth.accessToken != nil else {
            NetworkDebug.log("Push device sync skipped: missing JWT")
            return
        }
        guard let userID else {
            NetworkDebug.log("Push device sync skipped: missing user id")
            return
        }
        guard isSessionValid(for: userID, generation: syncSessionGeneration) else {
            NetworkDebug.log("Push device sync skipped: stale session")
            return
        }
        guard let token = currentToken, !token.isEmpty else {
            NetworkDebug.log("Push device sync skipped: missing APNs token")
            return
        }
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            NetworkDebug.log("Push device sync skipped: missing bundle id")
            return
        }

        let installationID: String
        do {
            installationID = try installationIDProvider.installationID()
        } catch {
            NetworkDebug.logError(error, prefix: "Push installation id unavailable")
            return
        }

        let syncKey = PushDeviceSyncKey(
            userID: userID,
            token: token,
            environment: PushEnvironment.current.rawValue,
            installationID: installationID
        )

        guard inFlightSyncKey == nil else {
            if inFlightSyncKey?.userID != userID {
                pendingSyncUserID = userID
            }
            NetworkDebug.log("Push device sync skipped: sync already in flight")
            return
        }

        guard lastSuccessfulSyncKey != syncKey else {
            NetworkDebug.log("Push device sync skipped: token already synced")
            return
        }

        inFlightSyncKey = syncKey
        defer {
            inFlightSyncKey = nil
            if let pendingUserID = pendingSyncUserID {
                pendingSyncUserID = nil
                Task { @MainActor [weak self] in
                    await self?.syncCurrentTokenIfPossible(userID: pendingUserID)
                }
            }
        }

        NetworkDebug.log(
            "Push device sync started environment=\(syncKey.environment) token=\(token.safeTokenDescription)"
        )

        let body = RegisterPushDeviceRequestBody(
            platform: "ios",
            token: token,
            environment: syncKey.environment,
            bundleId: bundleID,
            installationId: syncKey.installationID,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            deviceModel: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier,
            authorizationStatus: await center.notificationSettings().authorizationStatus.pushString
        )

        guard isSessionValid(for: userID, generation: syncSessionGeneration) else {
            NetworkDebug.log("Push device sync skipped: stale session before network send")
            return
        }

        do {
            _ = try await NetworkExecutor.shared.send(RegisterPushDeviceRequest(bodyValue: body))
            guard isSessionValid(for: userID, generation: syncSessionGeneration) else {
                NetworkDebug.log("Push device sync response ignored: stale session")
                return
            }
            lastSuccessfulSyncKey = syncKey
            NetworkDebug.log(
                "Push device sync succeeded environment=\(syncKey.environment) token=\(token.safeTokenDescription)"
            )
        } catch {
            NetworkDebug.logError(
                error,
                prefix: "Push device sync failed environment=\(syncKey.environment) token=\(token.safeTokenDescription)"
            )
        }
    }

    func unregisterCurrentDevice() async {
        await unregisterCurrentDevice(accessToken: APIAuth.accessToken)
    }

    func unregisterCurrentDevice(accessToken: String?) async {
        guard let accessToken, !accessToken.isEmpty else {
            NetworkDebug.log("Push device unregister skipped: missing JWT")
            return
        }

        await waitForInFlightSyncToFinish()

        let installationID: String
        do {
            installationID = try installationIDProvider.installationID()
        } catch {
            NetworkDebug.logError(error, prefix: "Push installation id unavailable")
            return
        }

        let body = UnregisterPushDeviceRequestBody(
            installationId: installationID,
            environment: PushEnvironment.current.rawValue
        )

        do {
            _ = try await NetworkExecutor.shared.send(
                UnregisterPushDeviceRequest(bodyValue: body, accessToken: accessToken)
            )
            lastSuccessfulSyncKey = nil
            NetworkDebug.log("Push device unregister succeeded")
        } catch {
            NetworkDebug.logError(error, prefix: "Push device unregister failed")
        }
    }

    func resetSessionState() {
        sessionGeneration += 1
        lastSuccessfulSyncKey = nil
        pendingSyncUserID = nil
    }

    private func isSessionValid(for userID: UUID, generation: Int) -> Bool {
        sessionGeneration == generation
            && SessionStore.shared.isFullyAuthenticated
            && SessionStore.shared.currentUser?.id == userID
            && APIAuth.accessToken != nil
    }

    private func waitForInFlightSyncToFinish() async {
        guard inFlightSyncKey != nil else { return }
        NetworkDebug.log("Push device unregister waiting for in-flight sync")

        let deadline = Date().addingTimeInterval(5)
        while inFlightSyncKey != nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }

        if inFlightSyncKey != nil {
            NetworkDebug.log("Push device unregister continuing after in-flight sync wait timeout")
        }
    }
}

private struct PushDeviceSyncKey: Equatable {
    let userID: UUID
    let token: String
    let environment: String
    let installationID: String
}

extension PushRegistrationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if let onNotificationTap {
            onNotificationTap(userInfo)
        } else {
            pendingNotificationTapUserInfo = userInfo
            NetworkDebug.log("Push notification tap buffered until routing coordinator is ready")
        }
    }

    private func deliverPendingNotificationTapIfNeeded() {
        guard let onNotificationTap, let userInfo = pendingNotificationTapUserInfo else { return }
        pendingNotificationTapUserInfo = nil
        onNotificationTap(userInfo)
    }
}

private extension UNAuthorizationStatus {
    var allowsAPNsRegistration: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    var pushString: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .provisional:
            return "provisional"
        case .ephemeral:
            return "ephemeral"
        @unknown default:
            return "unknown"
        }
    }
}

private extension String {
    var safeTokenDescription: String {
        guard count > 16 else { return "<redacted>" }
        return "\(prefix(8))...\(suffix(8))"
    }
}

extension Data {
    var lowercaseHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
