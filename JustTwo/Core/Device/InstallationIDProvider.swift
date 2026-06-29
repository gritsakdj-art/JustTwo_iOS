import Foundation
import Security

protocol InstallationIDProviding {
    func installationID() throws -> String
}

enum InstallationIDError: Error {
    case encodingFailed
    case decodingFailed
    case unexpectedStatus(OSStatus)
}

final class InstallationIDProvider: InstallationIDProviding {
    static let shared = InstallationIDProvider()

    private let service = "life.justtwo.ios"
    private let key = "justtwo.installation.id"

    private init() {}

    func installationID() throws -> String {
        if let existing = try loadString() {
            return existing
        }

        let id = UUID().uuidString
        try saveString(id)
        return id
    }

    private func saveString(_ value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw InstallationIDError.encodingFailed
        }

        try deleteString()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw InstallationIDError.unexpectedStatus(status)
        }
    }

    private func loadString() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw InstallationIDError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw InstallationIDError.decodingFailed
        }

        return value
    }

    private func deleteString() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw InstallationIDError.unexpectedStatus(status)
        }
    }
}
