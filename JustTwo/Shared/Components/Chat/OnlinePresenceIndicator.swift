import SwiftUI

struct OnlinePresenceIndicator: View {
    var size: CGFloat = 12
    var borderWidth: CGFloat = 2

    var body: some View {
        Circle()
            .fill(Color.green)
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

    func onlinePresenceRing(isOnline: Bool) -> some View {
        overlay {
            Circle()
                .strokeBorder(
                    isOnline ? Color.green : Color.hairline,
                    lineWidth: isOnline ? 3 : 2
                )
        }
    }
}
