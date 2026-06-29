import Foundation

@MainActor
final class ProfilePhotosStartupLoader {

    static let shared = ProfilePhotosStartupLoader()

    private var singleFlight = StartupSingleFlight()

    private init() {}

    func loadIfNeeded(force: Bool = false) async {
        await singleFlight.run(key: "profile-photos", force: force) {
            await ProfilePhotoStore.shared.loadPhotos(force: force)
        }
    }

    func reset() {
        singleFlight.reset()
    }
}
