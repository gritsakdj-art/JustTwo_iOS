# Startup Loading Flow

JustTwo iOS warms authenticated home data during splash and keeps it in shared stores so tabs do not reload on every visit.

## Goals

After session restore and profile availability:

1. User enters main UI with profile, conversations, badge state, and (when online) realtime subscriptions ready.
2. Recent chat messages preload in the background.
3. Opening a chat uses cached messages first, then refreshes from REST.
4. Logout/session clear resets all warmed state.
5. **Offline cold relaunch (PR15D):** token + cached user/profile snapshot → `MainTabView` without waiting for network.

## Architecture

```text
SplashViewModel
  ├─ Keychain token restore
  ├─ StartupSessionSnapshotStore.load (local user/profile)
  ├─ Network validation (/me + /profile/me) — recoverable when cache exists
  └─ AppStartupCoordinator.runCriticalLocalWarmup
        └─ ConversationsStartupLoader.loadLocalWarmupIfNeeded (SwiftData hydrate only)

After MainTabView (background):
  AppStartupCoordinator.runBackgroundNetworkWarmup
        ├─ MessengerSyncEngine hydrate + background delta sync
        ├─ ProfilePhotosStartupLoader
        ├─ ConversationsStartupLoader.refreshNetworkIfNeeded
        ├─ realtime connect + delta bootstrap
        ├─ ConversationAvatarsStartupLoader (critical + remaining)
        └─ MessagesStartupLoader (local-DB-first, PR15F)
        └─ MessengerMediaCacheService.runCleanupIfNeeded (PR15E, background)
```

### Coordinator and loaders

| Component | Path | Responsibility |
|-----------|------|----------------|
| `SplashViewModel` | `Bootstrap/SplashViewModel.swift` | Token restore, snapshot hydrate, network validation, offline route |
| `StartupSessionSnapshotStore` | `Core/Persistence/Startup/StartupSessionSnapshotStore.swift` | Persist last-known user/profile for offline splash |
| `StartupSessionValidationService` | `Bootstrap/Startup/StartupSessionValidationService.swift` | Background `/me` + `/profile/me` after offline entry |
| `AppStartupCoordinator` | `Bootstrap/Startup/AppStartupCoordinator.swift` | Critical local warmup + background network warmup, reset |
| `AppStartupWarmupStore` | `Bootstrap/AppStartupWarmupStore.swift` | Backward-compatible facade over coordinator |
| `ProfileStartupLoader` | `Bootstrap/Startup/ProfileStartupLoader.swift` | `/profile/me` single-flight load into `SessionStore` + snapshot persist |
| `ProfilePhotosStartupLoader` | `Bootstrap/Startup/ProfilePhotosStartupLoader.swift` | Wraps `ProfilePhotoStore.loadPhotos` (background) |
| `ConversationsStartupLoader` | `Bootstrap/Startup/ConversationsStartupLoader.swift` | Local hydrate + network refresh split |
| `MessagesStartupLoader` | `Bootstrap/Startup/MessagesStartupLoader.swift` | Background message preload |
| `ConversationAvatarsStartupLoader` | `Bootstrap/Startup/ConversationAvatarsStartupLoader.swift` | Background partner avatar preload |
| `ChatPartnerAvatarCache` | `Shared/Views/Chats/ChatPartnerAvatarCache.swift` | Download/cache helper for chat avatars |
| `MessageCacheStore` | `Shared/Views/Chats/MessageCacheStore.swift` | In-memory messages cache per conversation |
| `StartupSingleFlight` | `Bootstrap/Startup/StartupSingleFlight.swift` | Shared single-flight helper |

Each loader supports:

* `loadIfNeeded` / `preloadIfNeeded`
* `force` reload where applicable
* `reset` on session clear
* duplicate request coalescing

## Offline-capable splash (PR15D)

### Rules

| Condition | Route |
|-----------|-------|
| No token | `AuthView` |
| Token locally expired (`JWTPayloadReader`) | `AuthView` |
| Server `401` / invalid token | clear session → `AuthView` |
| Email not verified (server) | verification gate |
| Profile not found (server, online) | `ProfileSetup` |
| Network unavailable + cached user + cached profile + `emailVerified` | `MainTabView` (stale/offline session) |
| Network unavailable + no cached profile | recoverable splash error (not fake main) |
| Network success | fresh server state → save snapshot → main |

**Network failure ≠ invalid session.** Only confirmed `401` clears the session.

### Startup session snapshot

Stored in Application Support JSON (`startup-session-snapshot.json`):

* `UserResponse` safe fields (id, email, emailVerified, dates)
* `UserProfileDTO` safe fields (no signed URLs, no JWT)
* `updatedAt`

Token stays in Keychain only.

Snapshot written on:

* successful splash `/me` + `/profile/me`
* profile upsert (`ProfileSettingsView`)
* sign-in (user only, profile when available)

Cleared on logout via `AppStartupCoordinator.performReset()`.

### Offline UI (PR18)

* `MessengerUXStatusStore` combines network path (debounced), session connectivity, sync engine state, cache flags.
* `OfflineSessionBanner` in `MainTabView` for offline showing cache, connection restored refreshing, refresh failed (saved data preserved).
* `MessengerSubtleStatusStrip` in chats list and chat for refreshing / offline hints without blocking interaction.
* No endless spinner when offline with no cached chats/messages — dedicated empty states instead.
* Cached conversations/messages stay visible during background refresh and after refresh failure.

Legacy:

* `SessionStore.connectivityState` → `offlineUsingCache` / `validationPending`
* `StartupSessionValidationService` retries when network returns

## Critical vs background

### Critical local (before main UI, no network required)

Executed in splash when profile route is allowed:

* `waitForLogoutReset`
* hydrate conversation list from SwiftData (`ConversationListViewModel.loadLocalWarmupIfNeeded`)
* completes without `GET /conversations`, profile photos, or avatars

### Background network (after main UI or in parallel when online)

* `GET /sync/state` baseline
* profile photos
* `GET /conversations` REST refresh
* delivery acks
* realtime connect + delta bootstrap
* critical + remaining partner avatars
* message preload for top `15` conversations

Limits live in `StartupLoadingLimits`.

## Screen consumption rules

### Chats

* `ChatsView` uses `ConversationListViewModel.shared`.
* `ConversationListViewModel` hydrates from `MessengerLocalStore` first, then REST in background or on explicit refresh.
* REST success upserts conversation snapshots into local DB via `MessengerConversationCacheService`.
* Delta/realtime list updates also write local conversation cache (PR15B).
* `ChatAvatarView` reads `ProfilePhotoImageCache` by `avatarPhotoID` before any network request.
* Loader appears only when conversations are empty and list VM is loading.
* `.task` keeps a safety `loadIfNeeded`, which is a no-op after startup.

### Private chat

* `ChatViewModel.open` hydrates from `MessengerLocalStore` via `MessengerMessageCacheService` when `isLocalReadEnabled` (PR15C).
* In-memory `MessageCacheStore` is updated from local DB snapshots, then messages render immediately when cache exists.
* REST refresh still runs through cache loader with `force: true` and remains authoritative on success.
* Network failure does not clear cached messages; loading flags always terminate.
* Pagination persists older pages to local DB.
* Delivered/read acks run in background and do not block chat open when cache is shown.

### Profile / photos

* `ProfileView` and `ProfilePhotosView` skip `loadPhotos()` when startup already populated `ProfilePhotoStore`.
* Profile photos load in background network warmup, not on splash critical path.

## Realtime and cache

REST remains source of truth for opened chats.

Realtime updates:

* active chat → `ChatViewModel` + `MessageCacheStore`
* inactive cached conversation → `MessageCacheStore` only
* conversation list → `ConversationListViewModel`

Offline entry defers realtime connect until background validation succeeds.

Send/edit/delete/reaction in `ChatViewModel` also update cache.

## Reset paths

`SessionStore.clearSession()` triggers:

* `MessengerRealtimeCoordinator.stop()`
* realtime disconnect
* `MessengerBadgeStore.reset()`
* `StartupSessionValidationService.stopWatching()`
* `AppStartupCoordinator.scheduleLogoutReset()` (async; does not block `clearSession` return)
* `ProfilePhotoStore.reset()`
* local avatar/order caches

`scheduleLogoutReset()` runs `performReset()` on MainActor in a tracked task. The next authenticated warmup calls `await waitForLogoutReset()` first so a fast re-login cannot use stale in-memory or on-disk messenger state.

Coordinator `performReset()` also clears:

* `StartupSessionSnapshotStore`
* profile loader state
* photos/conversations startup loader keys
* messages preload task
* `MessageCacheStore`
* `MessengerOutbox`, `MessengerDeltaSyncService`, `ConversationListViewModel`
* `MessengerLocalStore.shared.resetAllMessengerData()` (SwiftData; awaited inside reset task)

## Manual smoke checklist (PR15D)

### Online existing user

1. Launch with network, token exists.
2. `/me` + `/profile/me` succeed.
3. Main UI appears; conversation list loads.
4. Chat opens.

### Offline cold relaunch with cache

1. Login online; open conversations and at least one chat.
2. Kill app; enable airplane mode; relaunch.
3. Splash must not hang or route to Auth.
4. Main UI opens; offline banner visible.
5. Cached conversations and messages visible.

### Offline with no cached profile

1. Token without profile snapshot; disable network; launch.
2. Recoverable splash state — not fake MainTabView.

### Invalid token

1. Server `401` → clear session → Auth.
2. Network timeout/offline must not be treated as `401`.

### Network returns

1. Start offline cached main; disable airplane mode.
2. Background validation succeeds; banner clears; REST/delta/realtime resume.

### Logout isolation

1. Login A, seed cache, logout, login B.
2. A's startup snapshot and messenger cache must not appear.

## PR15F — Messenger request optimization

### Goals

- `MessagesStartupLoader` local-DB-first: hydrate SwiftData → memory before REST.
- Skip redundant `GET /messages` on chat open when cache is fresh.
- Remove full `GET /conversations` on every chat pop (`ChatsView`).
- Offline fail-fast via `NetworkPathMonitor.shouldSkipNetworkBecauseOffline`.
- Delivery ack batch on conversation refresh runs in background.

### Startup message preload flow

```text
For each top conversation:
  1. messengerStartupMessagesLocalPreloadStarted
  2. Hydrate SwiftData → MessageCacheStore
  3. If fresh → messengerStartupMessagesNetworkPreloadSkippedFreshCache
  4. If stale local → background REST refresh
  5. If empty → REST preload (unless offline fail-fast)
```

### Chat open

```text
memory/local hydrate → UI
if cache fresh → messengerChatOpenNetworkRefreshSkippedFreshCache
else → REST refresh (non-blocking when UI already has messages)
manual refresh → always force REST
```

### ChatsView pop

Returning from chat no longer calls `refresh()`. List state comes from realtime/delta/local cache. Manual pull-to-refresh still forces REST.

### Offline fail-fast

When `NetworkPathMonitor` reports offline after first path update, message/conversation REST wrappers return immediately and preserve cached UI.

### Manual smoke checklist

1. **Startup online:** launch → conversations + chats open without obvious delay regression.
2. **Startup offline:** seed online → kill → airplane → relaunch → list + messages + PR15E images visible; no long timeout.
3. **Chat after preload:** launch online → wait warmup → open chat → diagnostics show skip or single fetch, not duplicate immediate GET.
4. **Manual refresh:** pull refresh in chat/list → REST still runs.
5. **Chat pop:** open chat → back → no full conversations refresh unless manual.
6. **Realtime:** receive message in list/chat → preview updates; open chat → realtime message not overwritten by stale REST.
7. **Offline fail-fast:** airplane → open cached chat → no long spinner; manual refresh fails quickly, cache preserved.
8. **Acks:** open unread chat → UI not frozen by ack network.
9. **Diagnostics export:** no body/signed URL/JWT/localPath.

## Deferred

## Related docs

* [Messenger request optimization (PR15F)](MessengerLocalStorage.md#pr15f--messenger-startuprequest-optimization)
* [Messenger local storage (PR15A–C)](MessengerLocalStorage.md)
* [Invite links and QR flow](InviteLinks.md)
* [Profile photos and avatar presentation](ProfilePhotos.md)
