import PhotosUI
import SwiftUI
import UIKit

struct AvatarCropEditorView: View {
    let initialImage: UIImage?
    let onSave: (Data) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem?
    @State private var isShowingPhotoPicker = false
    @State private var sourceImage: UIImage?
    @State private var viewportSize: CGSize = .zero
    @State private var offset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var accumulatedScale: CGFloat = 1

    private let cropSize: CGFloat = 280

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            header
            cropCard
            actionButtons
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .discoverShellBackground()
        .localizedNavigationTitle("profile.avatar_editor.title")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveCroppedAvatar()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                }
                .accessibilityLabel(Text("profile.avatar_editor.save"))
                .disabled(sourceImage == nil)
                .foregroundStyle(sourceImage == nil ? Color.secondaryText : Color.brandPrimary)
            }
        }
        .task {
            sourceImage = initialImage
        }
        .task(id: selectedItem) {
            await loadSelectedImage()
        }
        .photosPicker(isPresented: $isShowingPhotoPicker, selection: $selectedItem, matching: .images)
    }

    private var header: some View {
        Text("profile.avatar_editor.subtitle")
            .font(Font.App.manrope(size: 15, weight: .medium))
            .foregroundStyle(Color.secondaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.sm)
    }

    private var cropCard: some View {
        VStack(spacing: AppSpacing.lg) {
            cropArea
                .frame(maxWidth: .infinity)
                .frame(height: 360)

            if sourceImage != nil {
                HStack(spacing: 8) {
                    Image(systemName: "hand.draw")
                        .font(Font.App.caption(weight: .semibold))

                    Text("profile.avatar_editor.hint")
                        .font(Font.App.manrope(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.elevatedSurface, in: Capsule())
            }
        }
        .padding(.vertical, AppSpacing.lg)
        .padding(.horizontal, AppSpacing.sm)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: AppCornerRadius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.sheet, style: .continuous)
                .stroke(Color.hairline, lineWidth: 1)
        )
        .shadow(color: Color.discoverCardShadow.opacity(0.08), radius: 24, x: 0, y: 10)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                isShowingPhotoPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: sourceImage == nil ? "photo.badge.plus" : "photo.on.rectangle.angled")
                        .font(Font.App.manrope(size: 15, weight: .semibold))

                    Text(sourceImage == nil ? "profile.avatar_editor.choose_photo" : "profile.avatar_editor.replace_photo")
                        .font(Font.App.manrope(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color.onAccentText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.brandPrimaryGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.brandPrimaryGlow.opacity(0.22), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(.spring(pressedScale: 0.98, response: 0.2, dampingFraction: 0.75))

            if sourceImage != nil {
                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(Font.App.manrope(size: 15, weight: .semibold))

                        Text("profile.avatar_editor.delete")
                            .font(Font.App.manrope(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color.error)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.error.opacity(0.08), in: RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppCornerRadius.field, style: .continuous)
                            .stroke(Color.error.opacity(0.22), lineWidth: 1)
                    )
                }
                .buttonStyle(.spring(pressedScale: 0.98, response: 0.2, dampingFraction: 0.75))
            }
        }
    }

    private var cropArea: some View {
        ZStack {
            if let sourceImage {
                GeometryReader { geo in
                    let size = min(cropSize, min(geo.size.width, geo.size.height))
                    let viewport = CGSize(width: size, height: size)
                    let baseSize = baseImageSize(in: viewport, imageSize: sourceImage.size)

                    ZStack {
                        Image(uiImage: sourceImage)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: baseSize.width * scale,
                                height: baseSize.height * scale
                            )
                            .offset(offset)
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                            .contentShape(Circle())
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                            .onAppear {
                                viewportSize = viewport
                            }
                            .onChange(of: geo.size) { _, newSize in
                                let nextSize = min(cropSize, min(newSize.width, newSize.height))
                                let nextViewport = CGSize(width: nextSize, height: nextSize)
                                viewportSize = nextViewport
                                offset = clampedOffset(
                                    offset,
                                    imageSize: sourceImage.size,
                                    viewport: nextViewport,
                                    scale: scale
                                )
                                accumulatedOffset = offset
                            }
                            .highPriorityGesture(dragGesture.simultaneously(with: magnificationGesture))

                        cropOverlay(size: size)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                }
                .frame(height: 340)
            } else {
                Button {
                    isShowingPhotoPicker = true
                } label: {
                    emptyAvatarPlaceholder
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cropOverlay(size: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.primaryText.opacity(0.42))
                .mask {
                    Rectangle()
                        .overlay {
                            Circle()
                                .frame(width: size, height: size)
                                .blendMode(.destinationOut)
                        }
                }
                .compositingGroup()

            Circle()
                .stroke(Color.onAccentText.opacity(0.96), lineWidth: 2)
                .frame(width: size, height: size)

            Circle()
                .stroke(Color.brandPrimary.opacity(0.42), lineWidth: 6)
                .blur(radius: 5)
                .frame(width: size + 2, height: size + 2)

            Circle()
                .strokeBorder(Color.onAccentText.opacity(0.35), lineWidth: 1)
                .frame(width: size - 18, height: size - 18)
        }
        .allowsHitTesting(false)
    }

    private var emptyAvatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.fieldBackground)
                .frame(width: cropSize, height: cropSize)

            Circle()
                .stroke(Color.hairline, lineWidth: 1)
                .frame(width: cropSize, height: cropSize)

            VStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 72, weight: .regular))
                    .foregroundStyle(Color.secondaryText.opacity(0.82))

                Text("profile.avatar_editor.empty")
                    .font(Font.App.manrope(size: 15, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .frame(height: 340)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let candidate = CGSize(
                    width: accumulatedOffset.width + value.translation.width,
                    height: accumulatedOffset.height + value.translation.height
                )
                if let sourceImage {
                    offset = clampedOffset(candidate, imageSize: sourceImage.size, viewport: viewportSize, scale: scale)
                } else {
                    offset = candidate
                }
            }
            .onEnded { _ in
                accumulatedOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = min(max(accumulatedScale * value, 1), 5)
                scale = newScale
                if let sourceImage {
                    offset = clampedOffset(offset, imageSize: sourceImage.size, viewport: viewportSize, scale: newScale)
                }
            }
            .onEnded { _ in
                accumulatedScale = scale
                accumulatedOffset = offset
            }
    }

    @MainActor
    private func loadSelectedImage() async {
        guard let selectedItem else { return }
        if let data = try? await selectedItem.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            applySelectedImage(image)
        }
    }

    private func applySelectedImage(_ image: UIImage) {
        selectedItem = nil
        sourceImage = nil
        sourceImage = image
        resetTransforms()
    }

    private func resetTransforms() {
        offset = .zero
        accumulatedOffset = .zero
        scale = 1
        accumulatedScale = 1
    }

    private func saveCroppedAvatar() {
        guard let sourceImage,
              let rendered = renderTransformedImage(sourceImage),
              let avatarData = AvatarCropImagePipeline.encodeAvatarData(square: rendered)
        else { return }

        onSave(avatarData)
        dismiss()
    }

    private func renderTransformedImage(_ image: UIImage) -> UIImage? {
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = UIScreen.main.scale
        let outputSize = CGSize(width: cropSize, height: cropSize)
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: rendererFormat)
        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))

            let baseSize = baseImageSize(in: outputSize, imageSize: image.size)
            let scaledWidth = baseSize.width * scale
            let scaledHeight = baseSize.height * scale
            let scaledRect = CGRect(
                x: (outputSize.width - scaledWidth) / 2 + offset.width,
                y: (outputSize.height - scaledHeight) / 2 + offset.height,
                width: scaledWidth,
                height: scaledHeight
            )
            image.draw(in: scaledRect)
        }
    }

    private func baseImageSize(in viewport: CGSize, imageSize: CGSize) -> CGSize {
        guard viewport.width > 0, viewport.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return viewport
        }
        let scale = max(viewport.width / imageSize.width, viewport.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func clampedOffset(_ candidate: CGSize, imageSize: CGSize, viewport: CGSize, scale: CGFloat) -> CGSize {
        let baseSize = baseImageSize(in: viewport, imageSize: imageSize)
        let scaledWidth = baseSize.width * scale
        let scaledHeight = baseSize.height * scale
        let maxX = max(0, (scaledWidth - viewport.width) / 2)
        let maxY = max(0, (scaledHeight - viewport.height) / 2)
        return CGSize(
            width: min(max(candidate.width, -maxX), maxX),
            height: min(max(candidate.height, -maxY), maxY)
        )
    }
}

private enum AvatarCropImagePipeline {
    static func encodeAvatarData(square image: UIImage) -> Data? {
        let outputSize = CGSize(width: 512, height: 512)
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: rendererFormat)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: outputSize))
        }
        return resized.jpegData(compressionQuality: 0.82)
    }
}

#Preview {
    NavigationStack {
        AvatarCropEditorView(initialImage: nil, onSave: { _ in }, onDelete: { })
    }
}
