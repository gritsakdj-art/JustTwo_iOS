import UIKit

enum ProfilePhotoImagePipeline {

    nonisolated private static let maxDimension: CGFloat = 1024
    nonisolated private static let jpegQuality: CGFloat = 0.8

    nonisolated static func prepareJPEG(from data: Data) -> PreparedProfilePhoto? {
        guard let image = UIImage(data: data) else { return nil }
        return prepareJPEG(from: image)
    }

    nonisolated static func prepareJPEG(from image: UIImage) -> PreparedProfilePhoto? {
        let resized = resize(image, maxDimension: maxDimension)
        guard let jpegData = resized.jpegData(compressionQuality: jpegQuality) else { return nil }

        return PreparedProfilePhoto(
            data: jpegData,
            contentType: "image/jpeg",
            byteSize: Int64(jpegData.count),
            width: Int(resized.size.width.rounded()),
            height: Int(resized.size.height.rounded())
        )
    }

    static func prepareJPEG(from data: Data) async -> PreparedProfilePhoto? {
        await Task.detached(priority: .userInitiated) {
            Self.prepareJPEG(from: data)
        }.value
    }

    static func prepareJPEG(from image: UIImage) async -> PreparedProfilePhoto? {
        await Task.detached(priority: .userInitiated) {
            Self.prepareJPEG(from: image)
        }.value
    }

    nonisolated static func decodeImage(from data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(data: data)
        }.value
    }

    nonisolated static func jpegData(from image: UIImage, compressionQuality: CGFloat) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            image.jpegData(compressionQuality: compressionQuality)
        }.value
    }

    nonisolated private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1 else { return image }

        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
