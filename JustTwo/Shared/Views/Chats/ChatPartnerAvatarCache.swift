import Foundation
import UIKit

enum ChatPartnerAvatarCache {

    static func image(for photoID: UUID) -> UIImage? {
        ProfilePhotoImageCache.shared.image(for: photoID)
    }

    @MainActor
    static func preload(_ conversation: ChatConversationPreview) async {
        guard let photoID = conversation.avatarPhotoID else { return }
        if await ProfilePhotoImageCache.shared.loadImage(for: photoID) != nil {
            return
        }
        guard let url = conversation.avatarURL else { return }

        do {
            let (data, response) = try await ImageDownloadClient.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let uiImage = await ProfilePhotoImagePipeline.decodeImage(from: data) else {
                return
            }
            ProfilePhotoImageCache.shared.save(uiImage, for: photoID)
        } catch {
            return
        }
    }
}
