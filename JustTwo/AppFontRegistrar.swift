import CoreText
import Foundation

enum AppFontRegistrar {
    private static var didRegister = false

    private static let fontFiles = [
        "Manrope-Regular",
        "Manrope-Medium",
        "Manrope-SemiBold",
        "Manrope-Bold",
        "Manrope-ExtraBold"
    ]

    static func registerFonts() {
        guard !didRegister else { return }
        didRegister = true

        for fileName in fontFiles {
            registerFont(named: fileName)
        }
    }

    private static func registerFont(named fileName: String) {
        let url = Bundle.main.url(forResource: fileName, withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: fileName, withExtension: "ttf")

        guard let url else { return }

        var error: Unmanaged<CFError>?
        let didRegister = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)

        if !didRegister,
           let error = error?.takeRetainedValue(),
           !isAlreadyRegistered(error) {
            assertionFailure("Unable to register font \(fileName): \(error)")
        }
    }

    private static func isAlreadyRegistered(_ error: CFError) -> Bool {
        let nsError = error as Error as NSError
        return nsError.domain == kCTFontManagerErrorDomain as String
            && nsError.code == CTFontManagerError.alreadyRegistered.rawValue
    }
}
