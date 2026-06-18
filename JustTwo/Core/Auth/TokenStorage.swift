import Foundation

protocol TokenStorage {
    func saveToken(_ token: String) throws
    func loadToken() throws -> String?
    func deleteToken() throws
}

