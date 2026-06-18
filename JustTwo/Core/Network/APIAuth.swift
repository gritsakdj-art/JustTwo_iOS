import Foundation

enum APIAuth {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _accessToken: String?

    private enum StorageKey {
        static let accessToken = "session.accessToken"
        static let userID = "session.userID"
        static let userEmail = "session.userEmail"
    }

    static var accessToken: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _accessToken
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _accessToken = newValue
            UserDefaults.standard.set(newValue, forKey: StorageKey.accessToken)
        }
    }

    static var persistedUserID: UUID? {
        guard let rawValue = UserDefaults.standard.string(forKey: StorageKey.userID) else { return nil }
        return UUID(uuidString: rawValue)
    }

    static var persistedUserEmail: String? {
        UserDefaults.standard.string(forKey: StorageKey.userEmail)
    }

    static func restorePersistedSession() {
        lock.lock()
        defer { lock.unlock() }
        _accessToken = UserDefaults.standard.string(forKey: StorageKey.accessToken)
    }

    static func persist(user: UserResponse) {
        UserDefaults.standard.set(user.id.uuidString, forKey: StorageKey.userID)
        UserDefaults.standard.set(user.email, forKey: StorageKey.userEmail)
    }

    static func clear() {
        lock.lock()
        _accessToken = nil
        lock.unlock()

        UserDefaults.standard.removeObject(forKey: StorageKey.accessToken)
        UserDefaults.standard.removeObject(forKey: StorageKey.userID)
        UserDefaults.standard.removeObject(forKey: StorageKey.userEmail)
    }
}
