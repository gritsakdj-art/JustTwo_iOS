@testable import JustTwo
import Foundation
import Testing

@Suite("Deep Link Parser Tests")
struct DeepLinkParserTests {
    @Test("invite universal link parses token from path")
    func inviteLinkParsesToken() {
        let url = URL(string: "https://api.jtwo.online/invite/abc123")!
        let deepLink = DeepLinkParser.parse(url)

        #expect(deepLink == .invite(token: "abc123"))
    }

    @Test("email verification link still parses")
    func emailVerificationStillWorks() {
        let url = URL(string: "https://api.jtwo.online/auth/verify-email?token=abc")!
        let deepLink = DeepLinkParser.parse(url)

        #expect(deepLink == .emailVerification(token: "abc"))
    }

    @Test("password reset link still parses")
    func passwordResetStillWorks() {
        let url = URL(string: "https://api.jtwo.online/auth/reset-password?token=abc")!
        let deepLink = DeepLinkParser.parse(url)

        #expect(deepLink == .passwordReset(token: "abc"))
    }

    @Test("wrong host returns nil")
    func wrongHostReturnsNil() {
        let url = URL(string: "https://example.com/invite/abc123")!
        #expect(DeepLinkParser.parse(url) == nil)
    }

    @Test("empty invite token returns nil")
    func emptyInviteTokenReturnsNil() {
        let url = URL(string: "https://api.jtwo.online/invite/")!
        #expect(DeepLinkParser.parse(url) == nil)
    }

    @Test("invite token parses from pasted string")
    func inviteTokenFromString() {
        #expect(
            DeepLinkParser.inviteToken(
                from: "https://api.jtwo.online/invite/abc123"
            ) == "abc123"
        )
    }

    @Test("invalid pasted invite string returns nil")
    func invalidPastedInviteStringReturnsNil() {
        #expect(DeepLinkParser.inviteToken(from: "https://example.com/invite/abc") == nil)
        #expect(DeepLinkParser.inviteToken(from: "") == nil)
    }
}
