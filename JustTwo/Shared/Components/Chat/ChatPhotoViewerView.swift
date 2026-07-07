import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Fullscreen photo viewer for chat image attachments.
///
/// Supports pinch-to-zoom with panning, double tap to reset to the fitted size
/// and recenter, and dismissal via the close button or a downward swipe when
/// the photo is not zoomed in.
struct ChatPhotoViewerView: View {
    let attachment: ChatMessageAttachment

    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var loadFailed = false

    @State private var scale: CGFloat = 1
    @State private var gestureBaseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var gestureBaseOffset: CGSize = .zero
    @State private var dismissDragOffset: CGSize = .zero

    private static let maxScale: CGFloat = 4
    /// Allow a little rubber-banding past the limits during an active pinch.
    private static let pinchOvershoot: CGFloat = 1.25
    private static let dismissDistanceThreshold: CGFloat = 120
    private static let dismissVelocityThreshold: CGFloat = 320

    private var isZoomedIn: Bool { scale > 1.01 }

    /// Fades the backdrop while the photo is being dragged down to dismiss.
    private var backgroundOpacity: Double {
        let progress = min(1, abs(dismissDragOffset.height) / 320)
        return 1 - progress * 0.45
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()

                content(in: geometry.size)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .overlay(alignment: .topTrailing) {
            closeButton
        }
        .preferredColorScheme(.dark)
        .task {
            await loadImage()
        }
    }

    @ViewBuilder
    private func content(in containerSize: CGSize) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: containerSize.width, height: containerSize.height)
                .scaleEffect(scale)
                .offset(
                    x: offset.width + dismissDragOffset.width,
                    y: offset.height + dismissDragOffset.height
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    resetZoom()
                }
                .gesture(
                    dragGesture(in: containerSize)
                        .simultaneously(with: magnificationGesture(in: containerSize))
                )
                .accessibilityLabel(Text("chats.message.photo"))
                .accessibilityAddTraits(.isImage)
        } else if loadFailed {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("chats.photoViewer.loadFailed")
                    .font(Font.App.subheadline())
                    .foregroundStyle(.white.opacity(0.7))
            }
        } else {
            ProgressView()
                .tint(.white)
                .controlSize(.large)
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.14), in: Circle())
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
        }
        .padding(.trailing, 16)
        .padding(.top, 8)
        .accessibilityLabel(Text("chats.photoViewer.close"))
    }

    // MARK: Gestures

    private func magnificationGesture(in containerSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(
                    Self.maxScale * Self.pinchOvershoot,
                    max(1 / Self.pinchOvershoot, gestureBaseScale * value)
                )
            }
            .onEnded { _ in
                let settledScale = min(Self.maxScale, max(1, scale))
                let settledOffset = settledScale <= 1
                    ? .zero
                    : clampedOffset(offset, scale: settledScale, in: containerSize)

                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    scale = settledScale
                    offset = settledOffset
                }
                gestureBaseScale = settledScale
                gestureBaseOffset = settledOffset
            }
    }

    private func dragGesture(in containerSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if isZoomedIn {
                    offset = CGSize(
                        width: gestureBaseOffset.width + value.translation.width,
                        height: gestureBaseOffset.height + value.translation.height
                    )
                } else {
                    dismissDragOffset = value.translation
                }
            }
            .onEnded { value in
                if isZoomedIn {
                    let settled = clampedOffset(offset, scale: scale, in: containerSize)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        offset = settled
                    }
                    gestureBaseOffset = settled
                } else {
                    let distance = value.translation.height
                    let projected = value.predictedEndTranslation.height
                    if abs(distance) > Self.dismissDistanceThreshold
                        || abs(projected) > Self.dismissVelocityThreshold {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dismissDragOffset = .zero
                        }
                    }
                }
            }
    }

    private func resetZoom() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            scale = 1
            offset = .zero
            dismissDragOffset = .zero
        }
        gestureBaseScale = 1
        gestureBaseOffset = .zero
    }

    /// Keeps the zoomed photo edges pinned to the screen edges: panning stops
    /// once the visible edge of the scaled image reaches the container edge.
    private func clampedOffset(
        _ proposed: CGSize,
        scale: CGFloat,
        in containerSize: CGSize
    ) -> CGSize {
        guard let image else { return .zero }

        let fitted = fittedImageSize(for: image.size, in: containerSize)
        let maxX = max(0, (fitted.width * scale - containerSize.width) / 2)
        let maxY = max(0, (fitted.height * scale - containerSize.height) / 2)

        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    private func fittedImageSize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return containerSize
        }
        let ratio = min(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        return CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
    }

    // MARK: Loading

    private func loadImage() async {
        if let localFileURL = attachment.localFileURL,
           let localImage = UIImage(contentsOfFile: localFileURL.path) {
            image = localImage
            return
        }

        if let cached = ChatMessageImageCache.shared.image(for: attachment.id) {
            image = cached
            return
        }

        if let diskCached = await MessengerMediaCacheService.loadViewerImage(attachmentID: attachment.id) {
            ChatMessageImageCache.shared.save(diskCached, for: attachment.id)
            image = diskCached
            return
        }

        guard let downloadURL = attachment.downloadURL else {
            loadFailed = true
            return
        }

        do {
            let (data, response) = try await ImageDownloadClient.data(from: downloadURL)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let downloaded = UIImage(data: data) else {
                loadFailed = true
                return
            }
            ChatMessageImageCache.shared.save(downloaded, for: attachment.id)
            await MessengerMediaCacheService.storeViewerImage(downloaded, attachmentID: attachment.id)
            image = downloaded
        } catch {
            loadFailed = true
        }
    }
}

#Preview {
    ChatPhotoViewerView(
        attachment: ChatMessageAttachment(
            id: "preview",
            contentType: "image/jpeg",
            byteSize: 1_000,
            width: 1_024,
            height: 768,
            localFileURL: nil,
            downloadURL: nil,
            downloadUrlExpiresAt: nil
        )
    )
}
