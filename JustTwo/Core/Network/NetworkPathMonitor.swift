import Foundation
import Network

@MainActor
final class NetworkPathMonitor {

    static let shared = NetworkPathMonitor()

    private var monitor: NWPathMonitor?
    private var lastSignature: String?
    private var handlers: [UUID: () -> Void] = [:]
    private(set) var isNetworkSatisfied = true
    private(set) var hasReceivedPathUpdate = false

    #if DEBUG
    nonisolated(unsafe) static var testingForceOffline: Bool?
    #endif

    /// Skip REST only when the path monitor has reported offline at least once.
    var shouldSkipNetworkBecauseOffline: Bool {
        #if DEBUG
        if let testingForceOffline = Self.testingForceOffline {
            return testingForceOffline
        }
        #endif
        return hasReceivedPathUpdate && !isNetworkSatisfied
    }

    private init() {}

    @discardableResult
    func registerPathChangeHandler(_ handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        ensureMonitorRunning()
        return id
    }

    func unregisterHandler(_ id: UUID) {
        handlers.removeValue(forKey: id)
    }

    func unregisterAllHandlers() {
        handlers.removeAll()
    }

    private func ensureMonitorRunning() {
        guard monitor == nil else { return }
        monitor = NetworkPathMonitorFactory.make()
        NetworkDebug.log("NetworkPathMonitor started")
    }

    fileprivate func handlePathUpdate(_ path: NWPath) {
        let previousSignature = lastSignature
        let previousSatisfied = isNetworkSatisfied
        hasReceivedPathUpdate = true
        isNetworkSatisfied = path.status == .satisfied

        let signature = Self.signature(for: path)
        lastSignature = signature

        if let previousSignature {
            guard previousSignature != signature else { return }
            NetworkDebug.log("Network path changed \(previousSignature) → \(signature)")
            handlers.values.forEach { $0() }
        } else {
            NetworkDebug.log("Network path initial \(signature)")
            if previousSatisfied != isNetworkSatisfied {
                handlers.values.forEach { $0() }
            }
        }
    }

    private static func signature(for path: NWPath) -> String {
        let interfaces = path.availableInterfaces
            .map { "\($0.type)" }
            .sorted()
            .joined(separator: ",")
        return "\(path.status)-\(interfaces)-expensive:\(path.isExpensive)-constrained:\(path.isConstrained)"
    }
}

private enum NetworkPathMonitorFactory {

    nonisolated static func make() -> NWPathMonitor {
        let pathMonitor = NWPathMonitor()
        pathMonitor.pathUpdateHandler = PathUpdateScheduler.schedule
        pathMonitor.start(queue: DispatchQueue(label: "justtwo.network-path"))
        return pathMonitor
    }
}

private enum PathUpdateScheduler {

    nonisolated static func schedule(_ path: NWPath) {
        Task { @MainActor in
            NetworkPathMonitor.shared.handlePathUpdate(path)
        }
    }
}
