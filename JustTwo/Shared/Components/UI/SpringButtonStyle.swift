import SwiftUI

struct SpringButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96
    var pressedOpacity: Double = 1
    var isEnabled: Bool = true
    var response: Double = 0.22
    var dampingFraction: Double = 0.72

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .springButtonEffect(
                isPressed: configuration.isPressed && isEnabled,
                pressedScale: pressedScale,
                pressedOpacity: pressedOpacity,
                response: response,
                dampingFraction: dampingFraction
            )
    }
}

extension ButtonStyle where Self == SpringButtonStyle {
    static func spring(
        pressedScale: CGFloat = 0.96,
        pressedOpacity: Double = 1,
        isEnabled: Bool = true,
        response: Double = 0.22,
        dampingFraction: Double = 0.72
    ) -> SpringButtonStyle {
        SpringButtonStyle(
            pressedScale: pressedScale,
            pressedOpacity: pressedOpacity,
            isEnabled: isEnabled,
            response: response,
            dampingFraction: dampingFraction
        )
    }
}

extension View {
    func springButtonEffect(
        isPressed: Bool,
        pressedScale: CGFloat = 0.96,
        pressedOpacity: Double = 1,
        response: Double = 0.22,
        dampingFraction: Double = 0.72
    ) -> some View {
        scaleEffect(isPressed ? pressedScale : 1)
            .opacity(isPressed ? pressedOpacity : 1)
            .animation(.spring(response: response, dampingFraction: dampingFraction), value: isPressed)
    }
}
