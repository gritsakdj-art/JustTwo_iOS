import SwiftUI
import UIKit

struct RemoteProfilePhotoView: View {
    let photo: ProfilePhotoDTO
    var onLoadFailure: (() async -> Void)?

    @State private var displayedImage: UIImage?
    @State private var isLoadingRemote = false
    @State private var didRetry = false
    @State private var loadToken = 0

    var body: some View {
        ZStack {
            if let displayedImage {
                Image(uiImage: displayedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                failurePlaceholder
            }

            if isLoadingRemote, displayedImage == nil {
                ProgressView()
                    .tint(Color.brandPrimary)
            }
        }
        .clipped()
        .task(id: loadTaskID) {
            await loadImage()
        }
    }

    private var loadTaskID: String {
        "\(photo.id.uuidString)-\(photo.downloadUrl)-\(loadToken)"
    }

    private var failurePlaceholder: some View {
        ZStack {
            Color.discoverMockProfileGradient
            Image(systemName: "photo")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.onAccentText.opacity(0.72))
        }
    }

    @MainActor
    private func loadImage() async {
        if let cached = ProfilePhotoImageCache.shared.image(for: photo.id) {
            displayedImage = cached
            if photo.isPrimary {
                ProfilePhotoImageCache.shared.saveAvatarFallback(cached)
            }
        }

        guard let url = URL(string: photo.downloadUrl) else {
            await handleLoadFailureIfNeeded()
            return
        }

        isLoadingRemote = displayedImage == nil
        defer { isLoadingRemote = false }

        do {
            let (data, response) = try await ImageDownloadClient.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                await handleLoadFailureIfNeeded()
                return
            }

            ProfilePhotoImageCache.shared.save(image, for: photo.id)
            if photo.isPrimary {
                ProfilePhotoImageCache.shared.saveAvatarFallback(image)
            }
            displayedImage = image
            didRetry = false
        } catch {
            await handleLoadFailureIfNeeded()
        }
    }

    @MainActor
    private func handleLoadFailureIfNeeded() async {
        guard displayedImage == nil else { return }
        guard !didRetry else { return }
        didRetry = true
        await onLoadFailure?()
        loadToken += 1
    }
}
