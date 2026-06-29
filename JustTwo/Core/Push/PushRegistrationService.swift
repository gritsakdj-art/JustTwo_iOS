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
    func unregisterCurrentDevice() async
    func unregisterCurrentDevice(accessToken: String?) async
}

enum PushEnvironment: String {
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
    static let shared = PushRegistrationService()

    var onOpenMessage: ((UUID, UUID) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private let installationIDProvider: InstallationIDProviding
    private var currentToken: String?
    private var isSyncing = false

    init(installationIDProvider: InstallationIDProviding = InstallationIDProvider.shared) {
        self.installationIDProvider = installationIDProvider
    }

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
        NetworkDebug.log("APNs token received: \(token.safeTokenDescription)")

        Task { @MainActor [weak self] in
            await self?.syncCurrentTokenIfPossible()
        }
    }

    func handleDidFailToRegister(error: Error) {
        NetworkDebug.logError(error, prefix: "APNs registration failed")
    }

    func syncCurrentTokenIfPossible() async {
        guard !isSyncing else { return }
        guard APIAuth.accessToken != nil else {
            NetworkDebug.log("Push device sync skipped: missing JWT")
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

        isSyncing = true
        defer { isSyncing = false }

        let body = RegisterPushDeviceRequestBody(
            platform: "ios",
            token: token,
            environment: PushEnvironment.current.rawValue,
            bundleId: bundleID,
            installationId: installationID,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            deviceModel: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier,
            authorizationStatus: await center.notificationSettings().authorizationStatus.pushString
        )

        do {
            _ = try await NetworkExecutor.shared.send(RegisterPushDeviceRequest(bodyValue: body))
            NetworkDebug.log("Push device sync succeeded")
        } catch {
            NetworkDebug.logError(error, prefix: "Push device sync failed")
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
            NetworkDebug.log("Push device unregister succeeded")
        } catch {
            NetworkDebug.logError(error, prefix: "Push device unregister failed")
        }
    }
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
        guard let conversationRaw = userInfo[MessengerNotificationService.PayloadKey.conversationID] as? String,
              let messageRaw = userInfo[MessengerNotificationService.PayloadKey.messageID] as? String,
              let conversationID = UUID(uuidString: conversationRaw),
              let messageID = UUID(uuidString: messageRaw)
        else {
            NetworkDebug.log("Push notification tap received")
            return
        }

        onOpenMessage?(conversationID, messageID)
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
