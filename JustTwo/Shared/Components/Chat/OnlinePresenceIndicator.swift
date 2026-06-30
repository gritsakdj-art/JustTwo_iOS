import SwiftUI

private struct FilledPresenceRing: Shape {
    var lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: rect)
        path.addEllipse(in: rect.insetBy(dx: lineWidth, dy: lineWidth))
        return path
    }
}

struct OnlinePresenceIndicator: View {
    var size: CGFloat = 12
    var borderWidth: CGFloat = 2

    var body: some View {
        Circle()
            .fill(Color.discoverOnline)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(Color.surface, lineWidth: borderWidth)
            )
    }
}

extension View {
    func onlinePresenceIndicator(
        isVisible: Bool,
        size: CGFloat = 12,
        borderWidth: CGFloat = 2,
        alignment: Alignment = .bottomTrailing,
        offset: CGSize = CGSize(width: 2, height: 2)
    ) -> some View {
        overlay(alignment: alignment) {
            if isVisible {
                OnlinePresenceIndicator(size: size, borderWidth: borderWidth)
                    .offset(offset)
            }
        }
    }

    func onlinePresenceRing(
        isOnline: Bool,
        avatarSize: CGFloat,
        lineWidth: CGFloat = 1,
        spacing: CGFloat = 1,
        backgroundPadding: CGFloat = 1
    ) -> some View {
        let ringSize = avatarSize + (lineWidth + spacing) * 2
        let outerSize = ringSize + backgroundPadding * 2

        return ZStack {
            FilledPresenceRing(lineWidth: lineWidth)
                .fill(
                    isOnline ? Color.discoverOnline : Color.surface,
                    style: FillStyle(eoFill: true)
                )
                .frame(width: ringSize, height: ringSize)

            self
                .frame(width: avatarSize, height: avatarSize)
        }
        .frame(width: outerSize, height: outerSize)
        .fixedSize()
        .animation(.easeOut(duration: 0.2), value: isOnline)
    }
}
