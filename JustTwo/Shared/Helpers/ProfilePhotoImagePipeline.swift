import UIKit

enum ProfilePhotoImagePipeline {

    private static let maxDimension: CGFloat = 1024
    private static let jpegQuality: CGFloat = 0.8

    static func prepareJPEG(from data: Data) -> PreparedProfilePhoto? {
        guard let image = UIImage(data: data) else { return nil }
        return prepareJPEG(from: image)
    }

    static func prepareJPEG(from image: UIImage) -> PreparedProfilePhoto? {
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

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
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
