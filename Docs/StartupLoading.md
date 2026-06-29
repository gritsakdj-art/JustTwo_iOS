# Startup Loading Flow

JustTwo iOS warms authenticated home data during splash and keeps it in shared stores so tabs do not reload on every visit.

## Goals

After session restore and profile availability:

1. User enters main UI with profile, photos, conversations, badge state, and realtime subscriptions ready.
2. Recent chat messages preload in the background.
3. Opening a chat uses cached messages first, then refreshes from REST.
4. Logout/session clear resets all warmed state.

## Architecture

```text
SplashViewModel
  └─ ProfileStartupLoader.loadIfNeeded
  └─ AppStartupCoordinator.runCriticalWarmup
        ├─ ProfilePhotosStartupLoader
        ├─ ConversationsStartupLoader
        ├─ realtime activate (MessengerRealtimeCoordinator)
        └─ MessagesStartupLoader (background)
```

### Coordinator and loaders

| Component | Path | Responsibility |
|-----------|------|----------------|
| `AppStartupCoordinator` | `Bootstrap/Startup/AppStartupCoordinator.swift` | Critical warmup orchestration, dedupe, background scheduling, reset |
| `AppStartupWarmupStore` | `Bootstrap/AppStartupWarmupStore.swift` | Backward-compatible facade over coordinator |
| `ProfileStartupLoader` | `Bootstrap/Startup/ProfileStartupLoader.swift` | `/profile/me` single-flight load into `SessionStore` |
| `ProfilePhotosStartupLoader` | `Bootstrap/Startup/ProfilePhotosStartupLoader.swift` | Wraps `ProfilePhotoStore.loadPhotos` |
| `ConversationsStartupLoader` | `Bootstrap/Startup/ConversationsStartupLoader.swift` | Wraps `ConversationListViewModel.loadIfNeeded` + realtime activation |
| `MessagesStartupLoader` | `Bootstrap/Startup/MessagesStartupLoader.swift` | Background message preload |
| `ConversationAvatarsStartupLoader` | `Bootstrap/Startup/ConversationAvatarsStartupLoader.swift` | Critical + background partner avatar preload |
| `ChatPartnerAvatarCache` | `Shared/Views/Chats/ChatPartnerAvatarCache.swift` | Download/cache helper for chat avatars |
| `MessageCacheStore` | `Shared/Views/Chats/MessageCacheStore.swift` | In-memory messages cache per conversation |
| `StartupSingleFlight` | `Bootstrap/Startup/StartupSingleFlight.swift` | Shared single-flight helper |

Each loader supports:

* `loadIfNeeded` / `preloadIfNeeded`
* `force` reload where applicable
* `reset` on session clear
* duplicate request coalescing

## Critical vs background

### Critical (before main UI)

Executed in splash `.finishing` when profile exists, and after onboarding profile save:

* session restore (`SplashViewModel`)
* `/me` user load
* `/profile/me` via `ProfileStartupLoader`
* profile photos via `ProfilePhotoStore`
* conversations list via `ConversationListViewModel`
* partner avatars for the top `10` recent chats via `ConversationAvatarsStartupLoader`
* badge sync via conversation list refresh
* realtime connect (`SessionStore.connectRealtimeIfEligible`)
* conversation list realtime subscriptions

Non-fatal: photo/conversation network errors do not block splash routing.

### Background (after critical warmup)

* preload last `10` messages for top `15` recent conversations
* partner avatars for remaining conversations
* stored in `MessageCacheStore`
* does not block splash completion

Limits live in `StartupLoadingLimits`.

## Screen consumption rules

### Chats

* `ChatsView` uses `ConversationListViewModel.shared`.
* `ChatAvatarView` reads `ProfilePhotoImageCache` by `avatarPhotoID` before any network request.
* Loader appears only when conversations are empty and list VM is loading.
* `.task` keeps a safety `loadIfNeeded`, which is a no-op after startup.

### Private chat

* `ChatViewModel.open` reads `MessageCacheStore` first.
* If cache exists, messages render immediately without empty-state spinner.
* REST refresh still runs through cache loader with `force: true`.

### Profile / photos

* `ProfileView` and `ProfilePhotosView` skip `loadPhotos()` when startup already populated `ProfilePhotoStore`.

## Realtime and cache

REST remains source of truth for opened chats.

Realtime updates:

* active chat → `ChatViewModel` + `MessageCacheStore`
* inactive cached conversation → `MessageCacheStore` only
* conversation list → `ConversationListViewModel`

Send/edit/delete/reaction in `ChatViewModel` also update cache.

## Reset paths

`SessionStore.clearSession()` triggers:

* `MessengerRealtimeCoordinator.stop()`
* realtime disconnect
* `MessengerBadgeStore.reset()`
* `AppStartupCoordinator.reset()`
* `ProfilePhotoStore.reset()`
* local avatar/order caches

Coordinator reset also clears:

* profile loader state
* photos/conversations startup loader keys
* messages preload task
* `MessageCacheStore`
* `ConversationListViewModel`

## Adding a new preload domain

1. Create a focused loader/store with `loadIfNeeded`, `force`, `reset`, and single-flight.
2. Add it to `AppStartupCoordinator.runCriticalWarmup` if blocking, or schedule background task if optional.
3. Reset it from `AppStartupCoordinator.reset`.
4. Make screens read shared store state instead of fetching on every appear.
5. Document the domain here.

## Related docs

* [Invite links and QR flow](InviteLinks.md)
* [Profile photos and avatar presentation](ProfilePhotos.md)
