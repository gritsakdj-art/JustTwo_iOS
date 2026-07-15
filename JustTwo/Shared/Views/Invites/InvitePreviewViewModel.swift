import Foundation

struct InvitePreviewContent: Equatable {
    let inviterProfileID: UUID
    let displayName: String
    let bio: String?
    let city: String?
    let avatarURL: URL?
    let avatarPhotoID: UUID?
}

@MainActor
@Observable
final class InvitePreviewViewModel {
    enum State: Equatable {
        case loading
        case loaded(InvitePreviewContent)
        case accepting
        case unavailable(String)
        case failed(String)
        case blocked
    }

    let token: String

    private(set) var state: State = .loading
    private(set) var statusMessage: String?

    init(token: String) {
        self.token = token
    }

    func load(session: SessionStore, router: AppRouter) async {
        state = .loading
        statusMessage = nil

        guard session.isFullyAuthenticated else {
            state = .failed(String(localized: "invite.error.login_required"))
            return
        }

        do {
            let preview = try await InviteService.previewInvite(token: token)
            state = .loaded(Self.makeContent(from: preview))
        } catch let error as NetworkError {
            if error.shouldClearSession {
                session.clearSession()
                router.resetTo(.auth)
                return
            }

            if InviteErrorMapper.isUnavailable(error) {
                state = .unavailable(InviteErrorMapper.previewMessage(for: error))
            } else {
                state = .failed(InviteErrorMapper.previewMessage(for: error))
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func accept(session: SessionStore, router: AppRouter) async {
        guard case .loaded(let content) = state else { return }
        guard let requestUserID = session.currentUser?.id else { return }
        let requestToken = token
        state = .accepting
        statusMessage = nil

        do {
            let requestConnectionEpoch = PresenceStore.shared.currentRealtimeConnectionEpoch
            let response = try await InviteService.acceptInvite(token: requestToken)
            let profileID = try await MessengerSessionSupport.resolveCurrentProfileID(session: session)
            guard token == requestToken,
                  session.isFullyAuthenticated,
                  session.currentUser?.id == requestUserID else { return }
            PresenceStore.shared.applyFromConversation(
                response.conversation,
                source: .rest,
                sessionGeneration: PresenceStore.shared.currentSessionGeneration,
                requestConnectionEpoch: requestConnectionEpoch
            )
            let conversation = ChatUIMapping.conversationPreview(
                from: response.conversation,
                currentProfileID: profileID
            )
            router.openChatAfterInviteAccept(conversation)
        } catch let error as NetworkError {
            guard token == requestToken else { return }
            if error.shouldClearSession {
                session.clearSession()
                router.resetTo(.auth)
                return
            }
            state = .loaded(content)
            statusMessage = InviteErrorMapper.acceptMessage(for: error)
        } catch {
            guard token == requestToken else { return }
            state = .loaded(content)
            statusMessage = error.localizedDescription
        }
    }

    func block(session: SessionStore, router: AppRouter) async {
        guard case .loaded(let content) = state else { return }
        guard let requestUserID = session.currentUser?.id else { return }
        let requestToken = token
        statusMessage = nil

        do {
            _ = try await ProfileBlockService.blockProfile(profileID: content.inviterProfileID)
            guard token == requestToken,
                  session.isFullyAuthenticated,
                  session.currentUser?.id == requestUserID else { return }
            state = .blocked
            router.dismissInvitePreview()
        } catch let error as NetworkError {
            guard token == requestToken else { return }
            if error.shouldClearSession {
                session.clearSession()
                router.resetTo(.auth)
                return
            }
            statusMessage = error.userMessage
        } catch {
            guard token == requestToken else { return }
            statusMessage = error.localizedDescription
        }
    }

    private static func makeContent(from preview: InvitePreviewDTO) -> InvitePreviewContent {
        InvitePreviewContent(
            inviterProfileID: preview.creatorProfile.id,
            displayName: preview.creatorProfile.displayName,
            bio: preview.creatorProfile.bio,
            city: preview.creatorProfile.city,
            avatarURL: ChatUIMapping.avatarURL(from: preview.creatorProfile.primaryPhoto),
            avatarPhotoID: preview.creatorProfile.primaryPhoto?.id
        )
    }
}
