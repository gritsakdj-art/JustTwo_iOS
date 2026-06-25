import SwiftUI

struct ChatAvatarView: View {
    let title: String
    let photoURL: URL?
    let photoID: UUID?
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let photoURL {
                AsyncImage(url: photoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        initialsPlaceholder
                    @unknown default:
                        initialsPlaceholder
                    }
                }
            } else {
                initialsPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
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
