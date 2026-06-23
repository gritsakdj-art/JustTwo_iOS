import Foundation

@MainActor
@Observable
final class ProfilePhotoLocalOrderStore {

    static let shared = ProfilePhotoLocalOrderStore()

    private(set) var revision = 0

    private let defaults = UserDefaults.standard
    private let keyPrefix = "profile.photoOrder"

    private init() {}

    func orderedPhotoIDs(userID: UUID, photos: [ProfilePhotoDTO]) -> [UUID] {
        guard let saved = loadSavedOrder(userID: userID), !saved.isEmpty else {
            return defaultOrder(for: photos)
        }
        return merge(saved: saved, with: photos)
    }

    func saveOrder(_ photoIDs: [UUID], userID: UUID) {
        let payload = photoIDs.map(\.uuidString)
        defaults.set(payload, forKey: storageKey(userID: userID))
        revision += 1
    }

    func clear(userID: UUID) {
        defaults.removeObject(forKey: storageKey(userID: userID))
        revision += 1
    }

    func clearAll() {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(keyPrefix) }
            .forEach { defaults.removeObject(forKey: $0) }
        revision += 1
    }

    private func loadSavedOrder(userID: UUID) -> [UUID]? {
        guard let raw = defaults.stringArray(forKey: storageKey(userID: userID)) else {
            return nil
        }
        return raw.compactMap(UUID.init(uuidString:))
    }

    private func storageKey(userID: UUID) -> String {
        "\(keyPrefix).\(userID.uuidString)"
    }

    private func defaultOrder(for photos: [ProfilePhotoDTO]) -> [UUID] {
        let primary = photos.first(where: \.isPrimary)
        let others = photos
            .filter { $0.id != primary?.id }
            .sorted {
                if $0.position != $1.position {
                    return $0.position < $1.position
                }
                return ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture)
            }
        if let primary {
            return [primary.id] + others.map(\.id)
        }
        return others.map(\.id)
    }

    private func merge(saved: [UUID], with photos: [ProfilePhotoDTO]) -> [UUID] {
        let available = Set(photos.map(\.id))
        var merged = saved.filter { available.contains($0) }

        let defaults = defaultOrder(for: photos)
        for id in defaults where !merged.contains(id) {
            merged.append(id)
        }

        if let primary = photos.first(where: \.isPrimary)?.id,
           let primaryIndex = merged.firstIndex(of: primary),
           primaryIndex != 0 {
            merged.remove(at: primaryIndex)
            merged.insert(primary, at: 0)
        }

        return merged
    }
}
