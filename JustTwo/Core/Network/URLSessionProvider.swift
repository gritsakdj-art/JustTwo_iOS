import Foundation

enum URLSessionProvider: Sendable {

    private nonisolated static let lock = NSLock()
    private nonisolated(unsafe) static var generation = 0

    private final class SessionStore: @unchecked Sendable {
        private let lock = NSLock()

        nonisolated(unsafe) private var primary: URLSession
        nonisolated(unsafe) private var ephemeral: URLSession
        nonisolated(unsafe) private var forcedFresh: URLSession
        nonisolated(unsafe) private var lastResort: URLSession
        nonisolated(unsafe) private var splashPrimary: URLSession
        nonisolated(unsafe) private var splashEphemeral: URLSession

        nonisolated init() {
            primary = URLSessionProvider.makePrimarySession(label: "primary")
            ephemeral = URLSessionProvider.makeEphemeralSession(label: "ephemeral")
            forcedFresh = URLSessionProvider.makeForcedFreshSession(label: "forcedFresh")
            lastResort = URLSessionProvider.makeLastResortSession(label: "lastResort")
            splashPrimary = URLSessionProvider.makeSplashPrimarySession(label: "splashPrimary")
            splashEphemeral = URLSessionProvider.makeSplashEphemeralSession(label: "splashEphemeral")
        }

        nonisolated func getPrimary() -> URLSession {
            lock.lock()
            defer { lock.unlock() }
            return primary
        }

        nonisolated func getEphemeral() -> URLSession {
            lock.lock()
            defer { lock.unlock() }
            return ephemeral
        }

        nonisolated func getForcedFresh() -> URLSession {
            lock.lock()
            defer { lock.unlock() }
            return forcedFresh
        }

        nonisolated func getLastResort() -> URLSession {
            lock.lock()
            defer { lock.unlock() }
            return lastResort
        }

        nonisolated func getSplashPrimary() -> URLSession {
            lock.lock()
            defer { lock.unlock() }
            return splashPrimary
        }

        nonisolated func getSplashEphemeral() -> URLSession {
            lock.lock()
            defer { lock.unlock() }
            return splashEphemeral
        }

        nonisolated func resetAll() {
            lock.lock()
            let oldPrimary = primary
            let oldEphemeral = ephemeral
            let oldForcedFresh = forcedFresh
            let oldLastResort = lastResort
            let oldSplashPrimary = splashPrimary
            let oldSplashEphemeral = splashEphemeral

            primary = URLSessionProvider.makePrimarySession(label: "primary")
            ephemeral = URLSessionProvider.makeEphemeralSession(label: "ephemeral")
            forcedFresh = URLSessionProvider.makeForcedFreshSession(label: "forcedFresh")
            lastResort = URLSessionProvider.makeLastResortSession(label: "lastResort")
            splashPrimary = URLSessionProvider.makeSplashPrimarySession(label: "splashPrimary")
            splashEphemeral = URLSessionProvider.makeSplashEphemeralSession(label: "splashEphemeral")
            lock.unlock()

            oldPrimary.invalidateAndCancel()
            oldEphemeral.invalidateAndCancel()
            oldForcedFresh.invalidateAndCancel()
            oldLastResort.invalidateAndCancel()
            oldSplashPrimary.invalidateAndCancel()
            oldSplashEphemeral.invalidateAndCancel()

            NetworkDebug.log("URLSessionProvider: sessions reset (soft network restart)")
        }
    }

    private nonisolated static let store = SessionStore()

    nonisolated static var session: URLSession { store.getPrimary() }
    nonisolated static var fallbackSession: URLSession { store.getEphemeral() }
    nonisolated static var forcedFreshSession: URLSession { store.getForcedFresh() }
    nonisolated static var lastResortSession: URLSession { store.getLastResort() }
    nonisolated static var splashSession: URLSession { store.getSplashPrimary() }
    nonisolated static var splashEphemeralSession: URLSession { store.getSplashEphemeral() }
    nonisolated static var imageSession: URLSession { imageSessionStore }

    private nonisolated(unsafe) static var imageSessionStore: URLSession = makeImageSession(label: "image")

    nonisolated static func resetNetworkingSessions() {
        lock.lock()
        generation += 1
        lock.unlock()
        store.resetAll()

        let oldImageSession = imageSessionStore
        imageSessionStore = makeImageSession(label: "image")
        oldImageSession.invalidateAndCancel()
    }
}

private extension URLSessionProvider {

    nonisolated static func makePrimarySession(label: String) -> URLSession {
        makeAPISession(label: label, configuration: .default)
    }

    nonisolated static func makeEphemeralSession(label: String) -> URLSession {
        makeAPISession(label: label, configuration: .ephemeral)
    }

    nonisolated static func makeForcedFreshSession(label: String) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 45
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return makeAPISession(label: label, configuration: configuration)
    }

    nonisolated static func makeLastResortSession(label: String) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 45
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return makeAPISession(label: label, configuration: configuration)
    }

    nonisolated static func makeSplashPrimarySession(label: String) -> URLSession {
        makeTimedAPISession(
            label: label,
            configuration: .default,
            requestTimeout: APIConfiguration.splash.requestTimeout,
            resourceTimeout: APIConfiguration.splash.resourceTimeout
        )
    }

    nonisolated static func makeSplashEphemeralSession(label: String) -> URLSession {
        makeTimedAPISession(
            label: label,
            configuration: .ephemeral,
            requestTimeout: APIConfiguration.splash.requestTimeout,
            resourceTimeout: APIConfiguration.splash.resourceTimeout
        )
    }

    nonisolated static func makeTimedAPISession(
        label: String,
        configuration: URLSessionConfiguration,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) -> URLSession {
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout

        NetworkDebug.log("URLSession initialized [\(label)]")
        return URLSession(configuration: configuration)
    }

    nonisolated static func makeImageSession(label: String) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .returnCacheDataElseLoad

        NetworkDebug.log("URLSession initialized [\(label)]")
        return URLSession(configuration: configuration)
    }

    nonisolated static func makeAPISession(
        label: String,
        configuration: URLSessionConfiguration
    ) -> URLSession {
        configuration.waitsForConnectivity = false
        if configuration.timeoutIntervalForRequest == 60,
           configuration.timeoutIntervalForResource == 604_800 {
            configuration.timeoutIntervalForRequest = APIConfiguration.current.requestTimeout
            configuration.timeoutIntervalForResource = APIConfiguration.current.resourceTimeout
        }

        NetworkDebug.log("URLSession initialized [\(label)]")
        return URLSession(configuration: configuration)
    }
}
