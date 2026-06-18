import Foundation

enum URLSessionProvider {

    private static let lock = NSLock()
    private nonisolated(unsafe) static var generation = 0

    private final class SessionStore: @unchecked Sendable {
        private let lock = NSLock()

        private var primary: URLSession
        private var ephemeral: URLSession
        private var forcedFresh: URLSession
        private var lastResort: URLSession

        init() {
            primary = URLSessionProvider.makePrimarySession(label: "primary")
            ephemeral = URLSessionProvider.makeEphemeralSession(label: "ephemeral")
            forcedFresh = URLSessionProvider.makeForcedFreshSession(label: "forcedFresh")
            lastResort = URLSessionProvider.makeLastResortSession(label: "lastResort")
        }

        func getPrimary() -> URLSession {
            lock.lock()
            defer { lock.unlock() }
            return primary
        }

        func getEphemeral() -> URLSession {
            lock.lock()
            defer { lock.unlock() }
            return ephemeral
        }

        func getForcedFresh() -> URLSession {
            lock.lock()
            defer { lock.unlock() }
            return forcedFresh
        }

        func getLastResort() -> URLSession {
            lock.lock()
            defer { lock.unlock() }
            return lastResort
        }

        func resetAll() {
            lock.lock()
            let oldPrimary = primary
            let oldEphemeral = ephemeral
            let oldForcedFresh = forcedFresh
            let oldLastResort = lastResort

            primary = URLSessionProvider.makePrimarySession(label: "primary")
            ephemeral = URLSessionProvider.makeEphemeralSession(label: "ephemeral")
            forcedFresh = URLSessionProvider.makeForcedFreshSession(label: "forcedFresh")
            lastResort = URLSessionProvider.makeLastResortSession(label: "lastResort")
            lock.unlock()

            oldPrimary.invalidateAndCancel()
            oldEphemeral.invalidateAndCancel()
            oldForcedFresh.invalidateAndCancel()
            oldLastResort.invalidateAndCancel()

            NetworkDebug.log("URLSessionProvider: sessions reset (soft network restart)")
        }
    }

    private nonisolated static let store = SessionStore()

    nonisolated static var session: URLSession { store.getPrimary() }
    nonisolated static var fallbackSession: URLSession { store.getEphemeral() }
    nonisolated static var forcedFreshSession: URLSession { store.getForcedFresh() }
    nonisolated static var lastResortSession: URLSession { store.getLastResort() }

    nonisolated static func resetNetworkingSessions() {
        lock.lock()
        generation += 1
        lock.unlock()
        store.resetAll()
    }
}

private extension URLSessionProvider {

    static func makePrimarySession(label: String) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = APIConfiguration.current.requestTimeout
        configuration.timeoutIntervalForResource = APIConfiguration.current.resourceTimeout

        NetworkDebug.log("URLSession initialized [\(label)]")
        return URLSession(configuration: configuration)
    }

    static func makeEphemeralSession(label: String) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = APIConfiguration.current.requestTimeout
        configuration.timeoutIntervalForResource = APIConfiguration.current.resourceTimeout

        NetworkDebug.log("URLSession initialized [\(label)]")
        return URLSession(configuration: configuration)
    }

    static func makeForcedFreshSession(label: String) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 45
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        NetworkDebug.log("URLSession initialized [\(label)]")
        return URLSession(configuration: configuration)
    }

    static func makeLastResortSession(label: String) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 45
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        NetworkDebug.log("URLSession initialized [\(label)]")
        return URLSession(configuration: configuration)
    }
}
