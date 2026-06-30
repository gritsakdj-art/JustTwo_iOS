import SwiftUI
import UIKit

struct ChatAvatarView: View {
    let title: String
    let photoURL: URL?
    let photoID: UUID?
    var size: CGFloat = 52

    @State private var displayedImage: UIImage?

    var body: some View {
        Group {
            if let resolvedImage {
                Image(uiImage: resolvedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                initialsPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: loadTaskID) {
            await loadImageIfNeeded()
        }
    }

    private var resolvedImage: UIImage? {
        displayedImage ?? cachedImage
    }

    private var cachedImage: UIImage? {
        guard let photoID else { return nil }
        return ChatPartnerAvatarCache.image(for: photoID)
    }

    private var loadTaskID: String {
        "\(photoID?.uuidString ?? "none")-\(photoURL?.absoluteString ?? "none")"
    }

    @MainActor
    private func loadImageIfNeeded() async {
        if let cachedImage {
            displayedImage = cachedImage
            return
        }

        guard let photoURL else { return }

        do {
            let (data, response) = try await ImageDownloadClient.data(from: photoURL)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                return
            }

            if let photoID {
                ProfilePhotoImageCache.shared.save(image, for: photoID)
            }
            displayedImage = image
        } catch {
            return
        }
    }

    private var initialsPlaceholder: some View {
        Circle()
            .fill(Color.discoverVioletLight.opacity(0.35))
            .overlay(
                Text(title.prefix(1).uppercased())
                    .font(Font.App.manrope(size: size * 0.36, weight: .bold))
                    .foregroundStyle(Color.discoverViolet)
            )
    }
}
