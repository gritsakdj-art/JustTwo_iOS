import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
private final class TabBarInstantRevealOnPopController: UIViewController {
    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        guard parent == nil else { return }
        revealTabBarWithoutAnimation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isMovingFromParent else { return }
        revealTabBarWithoutAnimation()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isMovingFromParent else { return }
        revealTabBarWithoutAnimation()
    }

    private func revealTabBarWithoutAnimation() {
        guard let tabBar = resolvedTabBar else { return }

        UIView.performWithoutAnimation {
            tabBar.layer.removeAllAnimations()
            tabBar.isHidden = false
            tabBar.alpha = 1
            tabBar.transform = .identity
            tabBar.setNeedsLayout()
            tabBar.layoutIfNeeded()
            tabBar.superview?.layoutIfNeeded()
        }
    }

    private var resolvedTabBar: UITabBar? {
        var current: UIViewController? = parent ?? self
        while let controller = current {
            if let tabBar = controller.tabBarController?.tabBar {
                return tabBar
            }
            current = controller.parent
        }
        return nil
    }
}

private struct TabBarInstantRevealOnPopRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = TabBarInstantRevealOnPopController()
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
#endif

extension View {
    /// Reveals the system tab bar instantly when this screen is popped from a navigation stack.
    func tabBarInstantRevealOnPop() -> some View {
        #if canImport(UIKit)
        background(TabBarInstantRevealOnPopRepresentable())
        #else
        self
        #endif
    }
}
