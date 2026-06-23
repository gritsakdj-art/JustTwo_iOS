import CoreGraphics
import UIKit

struct AvatarCropTransform: Codable, Equatable, Sendable {
    var offsetX: Double
    var offsetY: Double
    var scale: Double

    static let identity = AvatarCropTransform(offsetX: 0, offsetY: 0, scale: 1)

    init(offsetX: Double, offsetY: Double, scale: Double) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
    }

    init(offset: CGSize, scale: CGFloat, viewport: CGSize) {
        let width = max(viewport.width, 1)
        let height = max(viewport.height, 1)
        offsetX = Double(offset.width / width)
        offsetY = Double(offset.height / height)
        self.scale = Double(scale)
    }

    func offset(in viewport: CGSize) -> CGSize {
        CGSize(
            width: CGFloat(offsetX) * viewport.width,
            height: CGFloat(offsetY) * viewport.height
        )
    }

    var scaleValue: CGFloat {
        CGFloat(scale)
    }
}

extension AvatarCropTransform {
    init(_ presentation: AvatarPresentationDTO) {
        self.init(
            offsetX: presentation.offsetX,
            offsetY: presentation.offsetY,
            scale: presentation.scale
        )
    }
}

extension AvatarPresentationDTO {
    init(_ transform: AvatarCropTransform) {
        self.init(
            offsetX: transform.offsetX.isFinite ? min(max(transform.offsetX, -2), 2) : 0,
            offsetY: transform.offsetY.isFinite ? min(max(transform.offsetY, -2), 2) : 0,
            scale: transform.scale.isFinite ? min(max(transform.scale, 1), 5) : 1
        )
    }
}

enum AvatarCropGeometry {
    static func baseImageSize(in viewport: CGSize, imageSize: CGSize) -> CGSize {
        guard viewport.width > 0, viewport.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return viewport
        }
        let fillScale = max(viewport.width / imageSize.width, viewport.height / imageSize.height)
        return CGSize(width: imageSize.width * fillScale, height: imageSize.height * fillScale)
    }

    static func clampedOffset(
        _ candidate: CGSize,
        imageSize: CGSize,
        viewport: CGSize,
        scale: CGFloat
    ) -> CGSize {
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

    static func drawRect(
        imageSize: CGSize,
        viewport: CGSize,
        offset: CGSize,
        scale: CGFloat
    ) -> CGRect {
        let baseSize = baseImageSize(in: viewport, imageSize: imageSize)
        let scaledWidth = baseSize.width * scale
        let scaledHeight = baseSize.height * scale
        return CGRect(
            x: (viewport.width - scaledWidth) / 2 + offset.width,
            y: (viewport.height - scaledHeight) / 2 + offset.height,
            width: scaledWidth,
            height: scaledHeight
        )
    }
}

struct AvatarCropSaveResult {
    let imageData: Data?
    let transform: AvatarCropTransform
    let didReplaceImage: Bool
}
