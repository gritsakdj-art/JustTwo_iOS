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
        if let photoID,
           let cached = await ProfilePhotoImageCache.shared.loadImage(for: photoID) {
            displayedImage = cached
            return
        }

        guard let photoURL else { return }

        do {
            let (data, response) = try await ImageDownloadClient.data(from: photoURL)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = await ProfilePhotoImagePipeline.decodeImage(from: data) else {
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
            .fill(initialsGradient)
            .overlay(
                Text(title.prefix(1).uppercased())
                    .font(Font.App.manrope(size: size * 0.36, weight: .bold))
                    .foregroundStyle(Color.onAccentText.opacity(0.92))
            )
    }

    private var initialsGradient: LinearGradient {
        let palette = initialsGradientPalette
        let index = stableTitleHash % palette.count
        let colors = palette[index]
        return LinearGradient(
            colors: [colors.0, colors.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var stableTitleHash: Int {
        let value = title.unicodeScalars.reduce(0) { partial, scalar in
            ((partial &* 31) &+ Int(scalar.value)) & 0x7fffffff
        }
        return max(0, value)
    }

    private var initialsGradientPalette: [(Color, Color)] {
        [
            (Color.discoverVioletLight, Color.discoverViolet),
            (Color.brandPrimary.opacity(0.92), Color.discoverVioletLight),
            (Color.discoverOnline.opacity(0.85), Color.brandPrimary.opacity(0.9)),
            (Color.discoverViolet.opacity(0.88), Color.brandPrimaryGlow.opacity(0.92))
        ]
    }
}
