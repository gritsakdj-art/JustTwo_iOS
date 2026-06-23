import Foundation

@MainActor
@Observable
final class ProfileAvatarCropStore {

    static let shared = ProfileAvatarCropStore()

    private(set) var revision = 0

    private let defaults = UserDefaults.standard
    private let keyPrefix = "profile.avatarCrop"

    private init() {}

    func transform(for photoID: UUID, userID: UUID) -> AvatarCropTransform? {
        guard let data = defaults.data(forKey: storageKey(photoID: photoID, userID: userID)) else {
            return nil
        }
        return try? JSONDecoder().decode(AvatarCropTransform.self, from: data)
    }

    func save(_ transform: AvatarCropTransform, photoID: UUID, userID: UUID) {
        guard let data = try? JSONEncoder().encode(transform) else { return }
        defaults.set(data, forKey: storageKey(photoID: photoID, userID: userID))
        revision += 1
    }

    func remove(photoID: UUID, userID: UUID) {
        defaults.removeObject(forKey: storageKey(photoID: photoID, userID: userID))
        revision += 1
    }

    func clear(userID: UUID) {
        let prefix = "\(keyPrefix).\(userID.uuidString)."
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { defaults.removeObject(forKey: $0) }
        revision += 1
    }

    func clearAll() {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(keyPrefix) }
            .forEach { defaults.removeObject(forKey: $0) }
        revision += 1
    }

    private func storageKey(photoID: UUID, userID: UUID) -> String {
        "\(keyPrefix).\(userID.uuidString).\(photoID.uuidString)"
    }
}
