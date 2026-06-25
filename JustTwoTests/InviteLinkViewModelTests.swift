@testable import JustTwo
import Foundation
import Testing
import UIKit

@Suite("Invite Link ViewModel Tests")
struct InviteLinkViewModelTests {
    @Test("resolveInviteURL uses server-provided inviteURL")
    func resolveInviteURLUsesServerValue() throws {
        let inviteID = UUID()
        let invite = InviteDTO(
            id: inviteID,
            type: "direct_conversation",
            status: "active",
            inviteURL: "https://api.jtwo.online/invite/server-token",
            expiresAt: nil,
            maxUses: 1,
            useCount: 0,
            createdAt: nil
        )

        let url = try #require(InviteLinkViewModel.resolveInviteURL(from: invite))
        #expect(url.absoluteString == "https://api.jtwo.online/invite/server-token")
    }

    @Test("resolveInviteURL returns nil when inviteURL missing")
    func resolveInviteURLMissing() {
        let invite = InviteDTO(
            id: UUID(),
            type: "direct_conversation",
            status: "active",
            inviteURL: nil,
            expiresAt: nil,
            maxUses: 1,
            useCount: 0,
            createdAt: nil
        )

        #expect(InviteLinkViewModel.resolveInviteURL(from: invite) == nil)
    }

    @Test("QR is generated from resolved invite URL")
    func qrGeneratedFromInviteURL() throws {
        let invite = InviteDTO(
            id: UUID(),
            type: "direct_conversation",
            status: "active",
            inviteURL: "https://api.jtwo.online/invite/qr-token",
            expiresAt: nil,
            maxUses: 1,
            useCount: 0,
            createdAt: nil
        )

        let url = try #require(InviteLinkViewModel.resolveInviteURL(from: invite))
        let image = try #require(QRCodeGenerator.generate(from: url.absoluteString))
        #expect(image.size.width > 0)
    }
}
