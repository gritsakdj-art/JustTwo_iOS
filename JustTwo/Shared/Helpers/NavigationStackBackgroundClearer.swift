import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum MainTabBarLayout {
    static let fallbackHeight: CGFloat = 64
}

struct TabBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = MainTabBarLayout.fallbackHeight

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

#if canImport(UIKit)
/// Clears opaque system backgrounds that `NavigationStack` inserts above the parent shell gradient.
private final class HostingBackgroundClearView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        clearHostingBackgrounds()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        clearHostingBackgrounds()
    }

    private func clearHostingBackgrounds() {
        NavigationStackHostingBackgroundClearer.clearHostingBackgrounds(startingAt: self)
    }
}

enum NavigationStackHostingBackgroundClearer {
    static func clearHostingBackgrounds(startingAt view: UIView) {
        var current: UIView? = view
        while let ancestor = current {
            if shouldClearBackground(for: ancestor) {
                ancestor.backgroundColor = .clear
                ancestor.isOpaque = false
            }
            current = ancestor.superview
        }
    }

    private static func shouldClearBackground(for view: UIView) -> Bool {
        let typeName = String(describing: type(of: view))
        if typeName.contains("UIHostingView") || typeName.contains("_UIHostingView") {
            return true
        }
        if typeName.contains("UILayoutContainerView") {
            return true
        }
        if typeName.contains("UINavigationController") || typeName.contains("NavigationController") {
            return true
        }
        return false
    }
}

private struct NavigationStackHostingBackgroundClearerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = HostingBackgroundClearView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        NavigationStackHostingBackgroundClearer.clearHostingBackgrounds(startingAt: uiView)
    }
}
#endif

extension View {
    func navigationStackHostingBackgroundClear() -> some View {
        #if canImport(UIKit)
        background(NavigationStackHostingBackgroundClearerRepresentable())
        #else
        self
        #endif
    }
}
