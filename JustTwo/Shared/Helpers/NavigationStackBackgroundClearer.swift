import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Clears opaque system backgrounds that `NavigationStack` inserts above the parent shell gradient.
private struct NavigationStackHostingBackgroundClearer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            Self.clearHostingBackgrounds(startingAt: uiView)
        }
    }

    private static func clearHostingBackgrounds(startingAt view: UIView) {
        var current: UIView? = view
        while let ancestor = current {
            let typeName = String(describing: type(of: ancestor))
            if typeName.contains("UIHostingView") || typeName.contains("_UIHostingView") {
                ancestor.backgroundColor = .clear
                ancestor.isOpaque = false
            }
            current = ancestor.superview
        }
    }
}

extension View {
    func navigationStackHostingBackgroundClear() -> some View {
        background(NavigationStackHostingBackgroundClearer())
    }
}
