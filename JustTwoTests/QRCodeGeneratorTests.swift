@testable import JustTwo
import Testing
import UIKit

@Suite("QR Code Generator Tests")
struct QRCodeGeneratorTests {
    @Test("non-empty string returns image")
    func nonEmptyStringReturnsImage() {
        let image = QRCodeGenerator.generate(from: "https://api.jtwo.online/invite/test-token")
        #expect(image != nil)
    }

    @Test("empty string returns nil")
    func emptyStringReturnsNil() {
        #expect(QRCodeGenerator.generate(from: "") == nil)
        #expect(QRCodeGenerator.generate(from: "   ") == nil)
    }

    @Test("generated image has non-zero size")
    func generatedImageHasSize() throws {
        let image = try #require(QRCodeGenerator.generate(from: "https://api.jtwo.online/invite/test-token"))
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }
}
