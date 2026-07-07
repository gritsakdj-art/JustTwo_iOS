import SwiftUI

struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    @State private var selectedTab: AppTab = .discover
    @State private var chatsViewModel = ConversationListViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            if session.shouldShowOfflineBanner {
                OfflineSessionBanner(connectivityState: session.connectivityState)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            TabView(selection: $selectedTab) {
                DiscoverView()
                    .tag(AppTab.discover)
                    .tabItem {
                        tabItem(for: .discover)
                    }

                MatchesView()
                    .tag(AppTab.matches)
                    .tabItem {
                        tabItem(for: .matches)
                    }

                chatsTab

                PlansView()
                    .tag(AppTab.plans)
                    .tabItem {
                        tabItem(for: .plans)
                    }

                ProfileView()
                    .tag(AppTab.profile)
                    .tabItem {
                        tabItem(for: .profile)
                    }
            }
            .tint(Color.discoverViolet)
            .toolbarBackground(.hidden, for: .tabBar)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: session.shouldShowOfflineBanner)
        .onAppear {
            selectedTab = router.selectedMainTab
        }
        .task {
            guard session.isFullyAuthenticated else { return }
            await chatsViewModel.loadIfNeeded(session: session, router: router)
            chatsViewModel.activateRealtime(session: session, router: router)
        }
        .onChange(of: router.selectedMainTab) { _, newTab in
            guard selectedTab != newTab else { return }
            selectedTab = newTab
        }
        .onChange(of: selectedTab) { _, newTab in
            guard router.selectedMainTab != newTab else { return }
            router.selectedMainTab = newTab
        }
        .fullScreenCover(item: invitePreviewPresentation) { presentation in
            InvitePreviewView(token: presentation.token)
                .environment(session)
                .environment(router)
        }
    }

    @ViewBuilder
    private var chatsTab: some View {
        ChatsView(viewModel: chatsViewModel)
            .tag(AppTab.chats)
            .tabItem {
                tabItem(for: .chats)
            }
            .badge(chatsViewModel.totalUnreadCount)
    }

    private func tabItem(for tab: AppTab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(systemName: tab.icon)
        }
    }

    private var invitePreviewPresentation: Binding<InvitePreviewPresentation?> {
        Binding(
            get: {
                router.presentedInvitePreviewToken.map(InvitePreviewPresentation.init(token:))
            },
            set: { newValue in
                if newValue == nil {
                    router.dismissInvitePreview()
                }
            }
        )
    }
}

private struct InvitePreviewPresentation: Identifiable {
    let token: String

    var id: String { token }
}

#Preview {
    MainTabView()
        .environment(AppRouter.shared)
        .environment(SessionStore.shared)
}
