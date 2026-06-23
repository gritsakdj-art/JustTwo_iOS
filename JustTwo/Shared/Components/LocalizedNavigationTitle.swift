import SwiftUI

private struct LocalizedNavigationTitleModifier: ViewModifier {
    let title: LocalizedStringResource
    @AppStorage("app.language") private var selectedLanguageRawValue = AppLanguage.system.rawValue

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(Font.App.manrope(size: 17, weight: .semibold))
                        .foregroundStyle(Color.discoverPrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .id(selectedLanguageRawValue)
                }
            }
    }
}

extension View {
    func localizedNavigationTitle(_ title: LocalizedStringResource) -> some View {
        modifier(LocalizedNavigationTitleModifier(title: title))
    }
}
