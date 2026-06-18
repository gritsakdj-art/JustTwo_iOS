import Foundation

enum APIAuth {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _accessToken: String?
    private nonisolated(unsafe) static var tokenStorage: TokenStorage = KeychainTokenStorage()

    static var accessToken: String? {
        lock.lock()
        defer { lock.unlock() }
        return _accessToken
    }

    static func restorePersistedSession() throws {
        let token = try tokenStorage.loadToken()
        lock.lock()
        _accessToken = token
        lock.unlock()
    }

    static func save(token: String) throws {
        try tokenStorage.saveToken(token)
        lock.lock()
        _accessToken = token
        lock.unlock()
    }

    static func clear() {
        lock.lock()
        _accessToken = nil
        lock.unlock()

        try? tokenStorage.deleteToken()
    }
}
