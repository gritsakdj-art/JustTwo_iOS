import Foundation
import UIKit

@MainActor
@Observable
final class InviteLinkViewModel {
    struct LoadedContent {
        let invite: InviteDTO
        let inviteURL: URL
        let qrImage: UIImage
    }

    enum State: Equatable {
        case idle
        case loading
        case loaded(LoadedContent)
        case failed(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading):
                return true
            case (.loaded(let left), .loaded(let right)):
                return left.invite.id == right.invite.id && left.inviteURL == right.inviteURL
            case (.failed(let left), .failed(let right)):
                return left == right
            default:
                return false
            }
        }
    }

    private(set) var state: State = .idle
    var didCopyLink = false
    var pastedLinkText = ""
    var pastedLinkError: String?

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        await refresh()
    }

    func refresh() async {
        state = .loading
        didCopyLink = false

        do {
            let invite = try await InviteService.createDirectInvite()
            guard let inviteURL = Self.resolveInviteURL(from: invite) else {
                state = .failed(String(localized: "invite.error.missing_url"))
                return
            }
            guard let qrImage = QRCodeGenerator.generate(from: inviteURL.absoluteString) else {
                state = .failed(String(localized: "invite.error.qr_generation_failed"))
                return
            }

            state = .loaded(
                LoadedContent(invite: invite, inviteURL: inviteURL, qrImage: qrImage)
            )
        } catch let error as NetworkError {
            state = .failed(error.userMessage)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func copyLink() {
        guard case .loaded(let content) = state else { return }
        UIPasteboard.general.string = content.inviteURL.absoluteString
        didCopyLink = true
    }

    func pasteFromClipboard() {
        pastedLinkError = nil
        if let clipboardText = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !clipboardText.isEmpty {
            pastedLinkText = clipboardText
        }
    }

    func parsedPastedInviteToken() -> String? {
        pastedLinkError = nil
        guard let token = DeepLinkParser.inviteToken(from: pastedLinkText) else {
            pastedLinkError = String(localized: "invite.error.invalid_pasted_link")
            return nil
        }
        return token
    }

    nonisolated static func resolveInviteURL(from invite: InviteDTO) -> URL? {
        guard let inviteURLString = invite.inviteURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !inviteURLString.isEmpty,
              let url = URL(string: inviteURLString)
        else { return nil }
        return url
    }
}
