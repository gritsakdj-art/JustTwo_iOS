import CoreGraphics
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Holds a view's latest global frame without publishing SwiftUI state updates.
/// Use for one-shot reads (e.g. long-press context menus) instead of `onGeometryChange`,
/// which can create layout feedback loops when attached to many scrolling rows.
@MainActor
final class SilentGlobalFrameReference {
    var rect: CGRect = .zero

    fileprivate var resolveCurrentRect: (() -> CGRect?)?

    func currentRect() -> CGRect {
        if let currentRect = resolveCurrentRect?() {
            rect = currentRect
        }
        return rect
    }
}

#if canImport(UIKit)
struct SilentGlobalFrameReader: UIViewRepresentable {
    let reference: SilentGlobalFrameReference

    func makeUIView(context: Context) -> SilentGlobalFrameCaptureView {
        let view = SilentGlobalFrameCaptureView()
        view.reference = reference
        reference.resolveCurrentRect = { [weak view] in
            guard let view else { return nil }
            return view.convert(view.bounds, to: nil)
        }
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: SilentGlobalFrameCaptureView, context: Context) {
        uiView.reference = reference
        reference.resolveCurrentRect = { [weak uiView] in
            guard let uiView else { return nil }
            return uiView.convert(uiView.bounds, to: nil)
        }
    }
}

final class SilentGlobalFrameCaptureView: UIView {
    weak var reference: SilentGlobalFrameReference?

    override func layoutSubviews() {
        super.layoutSubviews()
        reference?.rect = convert(bounds, to: nil)
    }
}
#else
struct SilentGlobalFrameReader: View {
    let reference: SilentGlobalFrameReference

    var body: some View {
        Color.clear
    }
}
#endif

extension View {
    func silentGlobalFrameReader(_ reference: SilentGlobalFrameReference) -> some View {
        background {
            SilentGlobalFrameReader(reference: reference)
        }
    }
}
