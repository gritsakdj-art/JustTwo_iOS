import Foundation
import Testing
@testable import JustTwo

@MainActor
struct AppStartupCoordinatorTests {

    @Test
    func resetClearsWarmupStateAndStores() {
        let coordinator = AppStartupCoordinator.shared
        coordinator.reset()

        #expect(coordinator.warmedUserID == nil)
        #expect(coordinator.isRunningCritical == false)
        #expect(ConversationListViewModel.shared.conversations.isEmpty)
        #expect(MessageCacheStore.shared.messages(for: UUID()) == nil)
    }
}
