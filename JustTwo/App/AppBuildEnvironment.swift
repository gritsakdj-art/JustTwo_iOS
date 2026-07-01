import Foundation
import StoreKit

enum AppBuildEnvironment {
    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private static var resolvedIsTestFlight: Bool?
    private static let resolutionLock = NSLock()
    private static var testFlightResolutionStarted = false

    static var isTestFlight: Bool {
        #if DEBUG
        return false
        #else
        return resolvedIsTestFlight ?? false
        #endif
    }

    static var showsInternalDiagnostics: Bool {
        isDebug || isTestFlight
    }

    static func refreshTestFlightStatus() async {
        let detected = await detectTestFlightFromAppTransaction()
        let didChange = resolutionLock.withLock {
            let previous = resolvedIsTestFlight
            resolvedIsTestFlight = detected
            return previous != detected
        }
        if didChange {
            NotificationCenter.default.post(name: .appBuildEnvironmentDidUpdate, object: nil)
        }
    }

    static func beginTestFlightResolutionIfNeeded() {
        let shouldStart = resolutionLock.withLock { () -> Bool in
            guard resolvedIsTestFlight == nil else { return false }
            guard !testFlightResolutionStarted else { return false }
            testFlightResolutionStarted = true
            return true
        }
        guard shouldStart else { return }

        Task {
            await refreshTestFlightStatus()
        }
    }

    private static func detectTestFlightFromAppTransaction() async -> Bool {
        guard let result = try? await AppTransaction.shared else { return false }
        guard case .verified(let appTransaction) = result else { return false }
        return appTransaction.environment == .sandbox
    }
}

extension Notification.Name {
    static let appBuildEnvironmentDidUpdate = Notification.Name("appBuildEnvironmentDidUpdate")
}
