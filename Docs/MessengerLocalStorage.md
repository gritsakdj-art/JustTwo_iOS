# Messenger Local Storage

On-device messenger persistence using SwiftData.

## Roadmap

| PR | Scope | Status |
|----|-------|--------|
| PR15A | SwiftData schema foundation, store API, logout reset | ✅ |
| PR15B | Cached conversation list (read + write from REST/delta/realtime) | ✅ |
| PR15C | Cached per-conversation message history | planned |
| PR16 | Persistent outbox | planned |
| PR17 | Full sync engine | planned |

## PR15B — Cached conversation list

Conversation list can hydrate from local DB on app/tab open, then refresh from REST. Delta and realtime keep the local conversation cache updated. Chat message screens still use REST + in-memory `MessageCacheStore` (PR15C).

### Behavior

```text
1. User opens app / conversations tab.
2. ConversationListViewModel loads cached conversations from MessengerLocalStore (if enabled).
3. If cache exists, UI shows it immediately (no empty spinner).
4. REST GET /conversations runs as before and remains authoritative on success.
5. REST success updates in-memory list and upserts local DB snapshots.
6. Delta/realtime updates in-memory list and patch/upsert local conversation cache.
7. Logout reset clears local conversation cache (PR15A hardening preserved).
```

### Offline / network failure

- If network fails but cache exists, cached conversations remain visible.
- Network failure does **not** wipe local cache.
- `refreshGeneration` prevents stale REST refresh calls from overwriting a newer refresh cycle.
- `listContentGeneration` prevents cache hydrate from overwriting fresher realtime/delta state that arrived during hydrate.
- REST apply merges per-conversation previews, keeping newer in-memory `lastMessageAt` when REST response is older.

### Feature flags

```swift
enum MessengerLocalStorageFeatureFlags {
    static let isLocalReadEnabled = false              // PR15C: message history reads
    static let isCachedConversationListEnabled = true // PR15B: conversation list
}
```

### Architecture

```text
ConversationListViewModel.performRefresh
  ├─ MessengerConversationCacheService.hydrateCachedPreviews
  │     └─ MessengerLocalStore.fetchLocalConversations
  │     └─ ChatUIMapping.conversationPreview(from: LocalConversationSnapshot)
  ├─ ConversationService.fetchConversations (REST baseline)
  └─ MessengerConversationCacheService.persistRESTConversations

MessengerDeltaSyncService.applyEvent
  └─ MessengerConversationCacheService.persistDeltaConversation

ConversationListViewModel realtime helpers
  └─ MessengerConversationCacheService.persistRealtimeMessage / persistRealtimeConversationRead / Updated
```

SwiftUI never reads `@Model` entities directly:

```text
LocalMessengerConversation → LocalConversationSnapshot → ChatConversationPreview → UI
```

### Local DB usage in PR15B

| Data | Persisted | Used for UI |
|------|-----------|-------------|
| Conversation list snapshots | yes | yes (hydration) |
| Denormalized lastMessage preview fields | yes | yes (list preview text) |
| lastMessage row in message table | yes (metadata only) | no (chat screen) |
| Full message history | no (beyond lastMessage) | no |
| Signed photo/message URLs | no | no |
| Persistent sync cursor | no | no |

### Privacy

- Signed `downloadUrl` / `uploadUrl` are **not** persisted in local messenger DB.
- Cached list avatars use `avatarPhotoID` only; `avatarURL` is nil until REST refresh.
- Diagnostics export must not include message bodies, signed URLs, JWT/Bearer, storage keys, or local file paths.
- Allowed diagnostic metadata: `count`, `durationMs`, `source`, sanitized IDs, `unreadCount`, `eventType`, `hasLastMessage`.

### Diagnostics (PR15B)

- `messengerConversationCacheLoadStarted` / `Succeeded` / `Failed` / `Empty`
- `messengerConversationCacheHydratedUI`
- `messengerConversationCacheNetworkRefreshStarted` / `Succeeded` / `Failed`
- `messengerConversationCacheUpsertStarted` / `Succeeded` / `Failed`
- `messengerConversationCacheDeltaApplied`
- `messengerConversationCacheRealtimeApplied`
- `messengerConversationCacheSkippedStale`

### Known limitations

- Cached avatars may show placeholder until REST provides fresh signed URL.
- Realtime partial `conversation.updated` patches only `lastMessageAt` locally (no full DTO).
- Reaction events do not change list preview unless backend includes updated `ConversationDTO`.
- PR14B in-memory delta cursor remains runtime source of truth (not persistent `LocalMessengerSyncMetadata` cursor).
- MainActor SwiftData writes are acceptable for conversation-list volume; no `ModelActor` refactor in PR15B.

### Manual smoke checklist (PR15B)

1. Fresh install/login → conversations load from network as before.
2. Open chat → messages still load from REST/current cache (not local DB history).
3. Load conversations, kill/relaunch → cached list appears quickly before/during network refresh.
4. Disable network after first load → relaunch → cached conversations still visible.
5. Device B sends message → Device A list updates → relaunch A → updated lastMessage in cache.
6. Image last message → list shows safe "Photo" preview; no signed URL in cache after relaunch.
7. Logout A, login B → B must not see A's cached conversations.
8. Export diagnostics → no signed URL/JWT/Bearer/message body/local paths.

## PR15A foundation

### SwiftData schema

Six messenger entities (plus `Item.self` in app container):

| Entity | Key fields | Notes |
|--------|------------|-------|
| `LocalMessengerConversation` | participant preview, `lastMessageAt`, denormalized lastMessage preview, `unreadCount` | No signed photo URLs |
| `LocalMessengerMessage` | `id`, `clientMessageID`, tombstone fields | lastMessage metadata only in PR15B |
| `LocalMessengerAttachment` | metadata only | no signed URL |
| `LocalMessengerReactionAggregate` | `id = messageID:emoji`, `count`, `reactedByMe` | |
| `LocalMessengerReceipt` | delivery/read watermarks | |
| `LocalMessengerSyncMetadata` | `lastAppliedRevision` | not used as runtime cursor yet |

### Thread / actor confinement

- `MessengerLocalStore` stack is `@MainActor`.
- Fresh `ModelContext` per operation; no concurrent context sharing.

### Logout reset

- `scheduleLogoutReset` / `waitForLogoutReset` + session generation guard (see [Startup loading](StartupLoading.md)).

### File map

| Path | Responsibility |
|------|----------------|
| `Core/Persistence/Messenger/MessengerConversationCacheService.swift` | PR15B cache hydrate/persist orchestration |
| `Core/Persistence/Messenger/MessengerLocalStore.swift` | Facade + feature flags |
| `Core/Persistence/Messenger/MessengerLocalMapping.swift` | DTO ↔ entity mapping |
| `Shared/Views/Chats/ViewModels/ConversationListViewModel.swift` | Cache-first list load |
| `Shared/Views/Chats/MessengerDeltaSyncService.swift` | Delta → local cache writes |
| `JustTwoTests/MessengerConversationCacheTests.swift` | PR15B focused tests |
| `JustTwoTests/MessengerLocalStoreTests.swift` | Store foundation tests |

### Tests

```bash
xcodebuild test -scheme JustTwo \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:JustTwoTests/MessengerConversationCacheTests \
  -only-testing:JustTwoTests/MessengerLocalStoreTests \
  -only-testing:JustTwoTests/AppStartupCoordinatorTests
```

## Related docs

- [Startup loading and reset flow](StartupLoading.md)
- [Realtime](Realtime.md)
