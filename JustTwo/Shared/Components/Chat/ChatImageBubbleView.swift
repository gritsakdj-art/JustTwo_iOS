import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Renders an image attachment inside a chat bubble with placeholder, custom loader,
/// failed state, and in-memory cache keyed by attachment identity.
struct ChatImageBubbleView: View {
    let attachment: ChatMessageAttachment
    let size: CGSize
    var cornerRadius: CGFloat = ChatImageBubbleLayout.cornerRadius
    var showsSendProgress: Bool = false
    var isMine: Bool = false
    var onTap: (() -> Void)?

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var reloadToken = 0

    private var cacheKey: String {
        ChatMessageImageCache.cacheKey(for: attachment)
    }

    private var showsCenteredLoader: Bool {
        (isLoading && image == nil) || (showsSendProgress && image != nil)
    }

    private var accessibilityLabel: Text {
        if loadFailed {
            return Text("chats.imageBubble.loadFailed")
        }
        if isLoading && image == nil {
            return Text("chats.imageBubble.loading")
        }
        if isMine {
            return Text("chats.imageBubble.outgoing")
        }
        return Text("chats.imageBubble.incoming")
    }

    var body: some View {
        // The photo is rendered as an overlay of the placeholder, not as a ZStack sibling:
        // `scaledToFill` reports an oversized width for wide photos, which would inflate
        // the ZStack beyond the computed size and push the photo past the bubble edge.
        // Overlays don't participate in layout, so the bubble size is driven purely by
        // the placeholder, clamped to the ideal `size` and to whatever width the bubble offers.
        placeholderBackground
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay {
                if showsCenteredLoader {
                    ZStack {
                        if showsSendProgress && image != nil {
                            Color.black.opacity(isMine ? 0.10 : 0.14)
                        }
                        JustTwoImageLoadingIndicator()
                    }
                }
            }
            .overlay {
                if loadFailed {
                    failedOverlay
                }
            }
        .frame(maxWidth: size.width)
        .frame(height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.glassBorderHighlight.opacity(0.22), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(image == nil ? [] : .isImage)
        .onTapGesture {
            if loadFailed {
                retryLoad()
            } else if image != nil {
                onTap?()
            }
        }
        .task(id: reloadToken) {
            await loadImageIfNeeded()
        }
    }

    private var placeholderBackground: some View {
        LinearGradient(
            colors: [
                Color.discoverMockLavender.opacity(0.62),
                Color.discoverMockPeach.opacity(0.48)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var failedOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)

            VStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 20, weight: .semibold))
                Text("chats.imageBubble.tapToRetry")
                    .font(Font.App.caption(size: 11, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.onAccentText.opacity(0.92))
            .padding(.horizontal, 10)
        }
    }

    private func retryLoad() {
        loadFailed = false
        image = nil
        reloadToken += 1
    }

    @MainActor
    private func loadImageIfNeeded() async {
        guard image == nil else { return }

        MessengerDiagnostics.event(
            .imageBubbleRenderStarted,
            metadata: renderMetadata(source: "unknown")
        )

        if let localFileURL = attachment.localFileURL,
           let localImage = UIImage(contentsOfFile: localFileURL.path) {
            applyLoadedImage(localImage, source: "local")
            MessengerDiagnostics.event(
                .imageBubbleUsedLocalFile,
                metadata: renderMetadata(source: "local")
            )
            return
        }

        if let cached = ChatMessageImageCache.shared.image(for: cacheKey) {
            applyLoadedImage(cached, source: "cache")
            MessengerDiagnostics.event(
                .imageCacheHit,
                metadata: renderMetadata(source: "cache")
            )
            return
        }

        if let diskCached = await MessengerMediaCacheService.loadBubbleImage(attachmentID: cacheKey) {
            ChatMessageImageCache.shared.save(diskCached, for: cacheKey)
            applyLoadedImage(diskCached, source: "disk")
            MessengerDiagnostics.event(
                .messengerMediaDiskCacheHit,
                metadata: renderMetadata(source: "disk")
            )
            return
        }

        MessengerDiagnostics.event(
            .imageCacheMiss,
            metadata: renderMetadata(source: "remote")
        )

        guard let downloadURL = attachment.downloadURL else {
            markLoadFailed(source: "missingRemoteURL")
            return
        }

        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        do {
            let (data, response) = try await ImageDownloadClient.data(from: downloadURL)
            guard !Task.isCancelled else { return }

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let downloaded = UIImage(data: data) else {
                markLoadFailed(source: "invalidResponse")
                return
            }

            ChatMessageImageCache.shared.save(downloaded, for: cacheKey)
            applyLoadedImage(downloaded, source: "remote")
            await MessengerMediaCacheService.storeBubbleImage(downloaded, attachmentID: cacheKey)
            MessengerDiagnostics.event(
                .imageBubbleUsedRemoteURL,
                metadata: renderMetadata(source: "remote")
            )
        } catch {
            guard !Task.isCancelled else { return }
            markLoadFailed(source: MessengerDiagnostics.sanitizeError(error))
        }
    }

    private func applyLoadedImage(_ loaded: UIImage, source: String) {
        image = loaded
        loadFailed = false
        MessengerDiagnostics.event(
            .imageBubbleRenderSucceeded,
            metadata: renderMetadata(source: source)
        )
    }

    private func markLoadFailed(source: String) {
        loadFailed = true
        MessengerDiagnostics.event(
            .imageBubbleRenderFailed,
            metadata: renderMetadata(source: source)
        )
    }

    private func renderMetadata(source: String) -> [String: String] {
        [
            "attachmentID": cacheKey,
            "contentType": attachment.contentType,
            "width": "\(attachment.width)",
            "height": "\(attachment.height)",
            "byteSize": "\(attachment.byteSize)",
            "source": source,
            "isMine": "\(isMine)"
        ]
    }
}

#if DEBUG
#Preview("Loading") {
    ChatImageBubbleView(
        attachment: ChatMessageAttachment(
            id: "preview-remote",
            contentType: "image/jpeg",
            byteSize: 1_000,
            width: 800,
            height: 1_200,
            localFileURL: nil,
            downloadURL: URL(string: "https://example.com/missing.jpg"),
            downloadUrlExpiresAt: nil
        ),
        size: CGSize(width: 200, height: 300)
    )
    .padding()
    .background(Color.discoverBackgroundGradient)
}
#endif
