import SwiftUI
import UIKit

struct ProfileAvatarFramedImageView: View {
    let image: UIImage
    let transform: AvatarCropTransform
    let size: CGFloat

    var body: some View {
        let viewport = CGSize(width: size, height: size)
        let offset = transform.offset(in: viewport)
        let baseSize = AvatarCropGeometry.baseImageSize(in: viewport, imageSize: image.size)
        let scale = transform.scaleValue

        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(
                width: baseSize.width * scale,
                height: baseSize.height * scale
            )
            .offset(offset)
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}
