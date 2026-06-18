import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension View {
    func hideKeyboardOnTap() -> some View {
        self
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    #if canImport(UIKit)
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                    #endif
                }
            )
    }
}
