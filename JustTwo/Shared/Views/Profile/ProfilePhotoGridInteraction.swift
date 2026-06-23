import SwiftUI

struct ProfilePhotoCellFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct ProfilePhotoGridFramesKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct ProfilePhotoCellFrameReporter: ViewModifier {
    let photoID: UUID

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ProfilePhotoCellFramesKey.self,
                    value: [photoID: geometry.frame(in: .named("profilePhotoGrid"))]
                )
            }
        }
    }
}

private struct ProfilePhotoGridWiggleModifier: ViewModifier {
    let isActive: Bool
    let seed: Double

    @State private var wiggle = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isActive ? (wiggle ? 1.4 : -1.4) : 0))
            .animation(
                isActive
                    ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true).delay(seed * 0.018)
                    : .spring(response: 0.28, dampingFraction: 0.82),
                value: wiggle
            )
            .onChange(of: isActive) { _, active in
                wiggle = active
            }
            .onAppear {
                wiggle = isActive
            }
    }
}

extension View {
    func profilePhotoCellFrame(photoID: UUID) -> some View {
        modifier(ProfilePhotoCellFrameReporter(photoID: photoID))
    }

    func profilePhotoGridWiggle(isActive: Bool, seed: Double) -> some View {
        modifier(ProfilePhotoGridWiggleModifier(isActive: isActive, seed: seed))
    }
}

enum ProfilePhotoGridLayout {
    static let spacing: CGFloat = 12
    static let columns = [
        GridItem(.flexible(), spacing: spacing),
        GridItem(.flexible(), spacing: spacing)
    ]

    static func photoIndex(at location: CGPoint, in frames: [UUID: CGRect], photos: [ProfilePhotoDTO]) -> Int? {
        for (index, photo) in photos.enumerated() {
            guard let frame = frames[photo.id], frame.contains(location) else { continue }
            return index
        }
        return nil
    }

    static func photoID(
        at location: CGPoint,
        in frames: [UUID: CGRect],
        photoIDs: [UUID],
        expansion: CGFloat = 10
    ) -> UUID? {
        for photoID in photoIDs {
            guard let frame = frames[photoID],
                  contains(location, in: frame, expansion: expansion) else {
                continue
            }
            return photoID
        }
        return nil
    }

    static func contains(_ point: CGPoint, in frame: CGRect, expansion: CGFloat = 10) -> Bool {
        frame.insetBy(dx: -expansion, dy: -expansion).contains(point)
    }
}
