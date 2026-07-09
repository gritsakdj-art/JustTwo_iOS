# Messenger Local Storage

On-device messenger persistence using SwiftData.

## Roadmap

| PR | Scope | Status |
|----|-------|--------|
| PR15A | SwiftData schema foundation, store API, logout reset | ✅ |
| PR15B | Cached conversation list (read + write from REST/delta/realtime) | ✅ |
| PR15C | Cached per-conversation message history + resilient chat loading | ✅ |
| PR15D | Offline-friendly splash + startup session snapshot | ✅ |
| PR15E | Persistent media disk cache for message attachments | ✅ |
| PR15F | Messenger startup/request optimization | ✅ |
| PR16A | Persistent text outbox | ✅ (pending manual smoke) |
| PR16B | Persistent image outbox + composer preview | ✅ (pending manual smoke) |
| PR16C | Outbox retry UI + network restore polish | ✅ (pending manual smoke) |
| PR17 | Full sync engine | planned |

## PR15D — Offline-friendly startup

Splash and critical warmup no longer require network when a usable cached session exists.

### Behavior

1. `StartupSessionSnapshotStore` persists safe user/profile fields (no JWT, no signed URLs).
2. Splash hydrates `SessionStore` from snapshot before network validation.
3. Recoverable network errors with cached user + profile → `MainTabView` with `offlineUsingCache`.
4. `401` still clears session; network timeout/offline is not treated as auth failure.
5. Critical warmup = local conversation hydrate only; REST/photos/avatars/realtime move to background.
6. `StartupSessionValidationService` re-validates when network returns.
7. Logout reset clears startup snapshot alongside messenger SwiftData.

### What stays separate from messenger SwiftData

| Data | Storage |
|------|---------|
| JWT | Keychain only |
| User/profile snapshot | Application Support JSON |
| Conversations/messages | SwiftData (`MessengerLocalStore`) |

### Manual smoke

See [Startup loading](StartupLoading.md) PR15D checklist.

## PR15E — Persistent media disk cache

Confirmed/received image attachments can survive relaunch from disk cache.

### Behavior

```text
1. Image bubble/viewer loads memory cache first.
2. On miss, reads Application Support media disk cache by attachmentID.
3. On disk hit, renders offline and updates mediaLastAccessedAt in SwiftData.
4. On disk miss with fresh downloadURL, downloads and stores thumb/full variants.
5. On disk miss without URL, shows safe placeholder (no crash).
6. Message delete removes disk files + clears metadata flags.
7. Background cleanup enforces quota/LRU and removes orphan files.
8. Logout clears entire media cache directory.
```

### What is cached

- Received images with server `attachmentID`
- Confirmed outgoing images after server returns `attachmentID`
- Thumbnail (bubble) and full (viewer) variants when downloaded

### What is not cached

- Pending outgoing `local-*` attachments before server ID
- Failed upload temp files (**legacy**) / durable outbox pending media (**PR16B** — `MessengerPendingMedia/`)
- Signed `downloadUrl`, `uploadUrl`, storage keys, image bytes in SwiftData

### SwiftData attachment fields (PR15E)

`hasLocalThumbnail`, `hasLocalFullImage`, `localThumbnailByteSize`, `localFullByteSize`, `mediaCachedAt`, `mediaLastAccessedAt`

**Schema note (v2):** PR15E adds optional attachment media metadata fields. If an on-device SwiftData store from PR15A–PR15D cannot be opened, `AppModelContainerFactory` recreates the store once (local messenger cache is rebuilt from REST/delta; media disk cache in Application Support is separate and preserved).

See [Messenger Media Cache](MessengerMediaCache.md) for storage layout, security, cleanup, and smoke checklist.

## PR15F — Messenger startup/request optimization

Reduces redundant REST calls while keeping REST authoritative and realtime/delta repair paths.

### Behavior

```text
1. MessagesStartupLoader hydrates SwiftData messages into MessageCacheStore first.
2. If local/memory cache is fresh (newest message >= conversation.lastMessageAt or memory TTL), REST preload is skipped.
3. Stale local cache still shows immediately; REST refresh runs in background.
4. Chat open uses force:false when cache is fresh — no duplicate GET /messages after preload.
5. Manual pull-to-refresh still forces REST.
6. ChatsView no longer runs full GET /conversations on every chat pop.
7. Known offline (NetworkPathMonitor) skips REST for messages/conversations without waiting for timeout.
8. Delivery/read acks on conversation list refresh run in background — do not block list UI.
```

### Freshness policy (`MessengerCacheFreshnessPolicy`)

| Rule | Value |
|------|-------|
| Memory cache TTL | 180s |
| Conversation list refresh TTL | 120s |
| Message freshness | `newestLocalMessage.createdAt >= conversation.lastMessageAt` (1s tolerance) |

Startup preload skip uses message timeline only. Chat open may also skip on memory TTL (180s) when timeline data is unavailable or already satisfied.

### What still refreshes from REST

- Manual pull-to-refresh (chat or list)
- Empty or stale local/memory cache
- Startup preload when local cache empty
- Background refresh when local cache is stale
- Delta/realtime updates (unchanged)

### Known limitations

- Freshness uses conversation `lastMessageAt` from list preview; rare clock/skew edge cases may trigger extra REST.
- `NetworkPathMonitor` offline skip requires at least one path update; until then requests fail gracefully on error.
- Stale local cache + background REST may briefly show older messages until refresh completes (realtime can still patch).

### Manual smoke

See [Startup loading](StartupLoading.md) PR15F checklist.

## PR15C — Cached messages per conversation

Chat screen opens from local cached messages when available, then REST remains authoritative refresh.

### Behavior

```text
1. User opens a chat.
2. ChatViewModel hydrates in-memory MessageCacheStore from MessengerLocalStore (if enabled).
3. If cached messages exist, UI shows them immediately (no endless spinner).
4. REST GET /conversations/:id/messages runs as authoritative refresh when cache is stale, empty, or manually requested (PR15F).
5. REST success merges in-memory state and upserts local DB message rows.
6. Pagination writes older pages to local DB.
7. Delta/realtime message events update in-memory state and persist to local message cache.
8. Network failure does NOT clear cached messages.
9. Stale/cancelled network loads do NOT overwrite current chat.
10. Logout reset clears local message cache (PR15A hardening preserved).
```

### Offline / network failure (chat)

- If network fails but local cache exists, cached messages remain visible.
- Local DB hydrate runs **before** network using `session.currentProfile?.id` when available.
- When cache is shown, REST refresh runs in the **background** without blocking `open()`.
- `isLoading` terminates on success, failure, cancellation, and stale generation.
- `isAwaitingInitialMessagePage` is `true` only when `isLoading && messages.isEmpty` (no blank-screen hang on partial cache).
- Empty cache + network failure shows recoverable error state, not endless spinner.
- Manual pull-to-refresh / `reload()` can recover after failure.

### Anti-stale protections

- `ChatViewModel.lifecycleGeneration` — stale `open()`/`loadMessages` work is ignored after `close()`/`reload()`.
- `ChatViewModel.messageContentGeneration` — local DB hydrate cannot overwrite fresher realtime/delta mutations.
- `ChatViewModel.messageLoadGeneration` + `MessageCacheStore.loadGenerations` — stale REST/pagination responses are ignored per conversation.
- `MessageCacheStore.cancelLoad` — in-flight refresh cancelled on chat reload/close.
- Conversation list anti-stale (`refreshGeneration`, `listContentGeneration`) unchanged from PR15B.

### Delta/realtime persistence

- Delta `message.created` / `message.edited` / `message.deleted` persist via `MessengerMessageCacheService`.
- Delta reactions persist when event includes full `MessageDTO` snapshot.
- Delta `conversation.read` / `conversation.delivered` persist receipts (monotonic).
- Realtime `message.created` / `message.edited` / `message.deleted` persist to local DB.
- **Limitation:** realtime `reaction.added` / `reaction.removed` without full `MessageDTO` update in-memory UI only; local DB is repaired on next delta/REST refresh.

### Optimistic sends (PR15C limitation)

- In-memory optimistic text/image messages still appear immediately.
- Server confirmation reconciles by `clientMessageID` and persists to local DB.
- Failed in-memory outbox remains in-memory only until PR16.
- After app kill, unsent optimistic messages may be lost until PR16.

### Image messages

- Attachment metadata persisted: `attachmentID`, `contentType`, `byteSize`, `width`, `height`, `localCacheKey`.
- Signed `downloadUrl` / `uploadUrl` / storage keys are **not** persisted.
- Cached image bubble shows placeholder until REST provides fresh URL, memory cache, or **disk cache (PR15E)**.
- Deleted image messages do not render stale attachments.

### Architecture (PR15C)

```text
ChatViewModel.open / loadMessages
  ├─ MessengerMessageCacheService.hydrateCachedMessages
  ├─ MessageCacheStore.loadRecentMessagesIfNeeded (REST)
  └─ MessageCacheStore.loadOlderMessages (pagination)

MessengerDeltaSyncService / MessengerRealtimeCoordinator
  └─ MessengerMessageCacheService persist hooks
```

### Diagnostics (PR15C)

See `messengerMessageCache*` and `messengerMessageNetwork*` / `messengerMessagePagination*` events in `MessengerDiagnostics`.

### Manual smoke checklist (PR15C)

1. Load chat with network → kill/relaunch → cached messages appear before/during REST refresh.
2. Disable network after cache warm → reopen chat → messages visible, no endless spinner.
3. Empty cache + no network → recoverable error, not spinner forever.
4. Realtime/delta message while offline → reconnect → relaunch → message from local cache.
5. Edit/delete/reaction → relaunch → cached state correct.
6. Image after relaunch → no raw URL/crash.
7. Logout isolation between accounts.
8. Diagnostics export privacy-safe.

## PR15B — Cached conversation list

Conversation list can hydrate from local DB on app/tab open, then refresh from REST. Delta and realtime keep the local conversation cache updated.

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
    static let isLocalReadEnabled = true               // PR15C: message history reads
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
| lastMessage row in message table | yes | yes (list preview + chat cache) |
| Full message history | yes (PR15C) | yes (chat hydration) |
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
| `Core/Persistence/Messenger/MessengerMessageCacheService.swift` | PR15C message cache hydrate/persist orchestration |
| `Core/Persistence/Messenger/MessengerLocalStore.swift` | Facade + feature flags |
| `Core/Persistence/Messenger/MessengerLocalMapping.swift` | DTO ↔ entity mapping |
| `Shared/Views/Chats/ViewModels/ConversationListViewModel.swift` | Cache-first list load |
| `Shared/Views/Chats/ViewModels/ChatViewModel.swift` | Cache-first chat load + resilient loading |
| `Shared/Views/Chats/MessageCacheStore.swift` | In-memory cache + REST persist hooks |

## PR16A — Persistent text outbox

Text-only durable send queue stored alongside messenger SwiftData cache.

### Relationship to local message cache

| Layer | Role |
|-------|------|
| `LocalMessengerMessage` | Confirmed/hydrated server messages (+ optional `localState` for UI) |
| `LocalMessengerOutboxItem` | Pending/failed **outgoing text** jobs with resend `body` |
| `MessageCacheStore` | Runtime optimistic bubbles + merge/reconcile |
| `MessengerOutbox` | In-memory send coordinator (text jobs persisted before pump) |

Outbox rows are **not** a replacement for confirmed message cache. On success, outbox row is deleted and confirmed `MessageDTO` is persisted via existing `MessengerMessageCacheService` paths.

### Schema note (v3)

PR16A adds `LocalMessengerOutboxItem`. Schema version is `3` (`MessengerPersistence.schemaVersion`). If the on-device store cannot open, `AppModelContainerFactory` recreates it once (same policy as PR15E v2 migration).

See [Messenger Outbox](MessengerOutbox.md) for lifecycle, retry, reconciliation, and privacy rules.

## PR16B — Persistent image outbox + pending media

Outgoing image sends with optional caption survive network failure, upload failure, create-message failure, and app relaunch.

### `LocalMessengerPendingMedia`

| Field | Stored | Forbidden |
|-------|--------|-----------|
| `pendingMediaID`, `clientMessageID`, `conversationID` | ✅ | |
| `localRelativePath` (relative only) | ✅ | absolute paths |
| `contentType`, `byteSize`, `width`, `height` | ✅ | |
| Image bytes | | ❌ |
| `uploadUrl`, `downloadUrl`, `storageKey` | | ❌ |

### Image outbox linkage

`LocalMessengerOutboxItem` for `kind=image`:

- `body` — optional caption/comment for retry (not logged in diagnostics)
- `pendingMediaID` — links to `LocalMessengerPendingMedia`
- Same status lifecycle as text (`pending` / `sending` / `failed` / …)

On success or logout: `deleteOutboxItem` / `resetAllMessengerData` deletes both SwiftData rows and pending media files.

### Schema note (v4)

PR16B adds `LocalMessengerPendingMedia` and `pendingMediaID` on outbox rows. Schema version is `4` (`MessengerPersistence.schemaVersion`).

### File map (PR16B additions)

| Path | Responsibility |
|------|----------------|
| `Core/Persistence/Messenger/Entities/LocalMessengerPendingMedia.swift` | SwiftData pending media metadata |
| `Core/Persistence/Messenger/Media/MessengerPendingMediaStore.swift` | Application Support pending file I/O |
| `Shared/Views/Chats/ChatImagePreparer.swift` | Persistent + preview image preparation |
| `Shared/Components/Chat/MessageInputView.swift` | Composer image preview + remove |
| `JustTwoTests/MessengerPendingMediaStoreTests.swift` | Pending media store tests |

## PR16C — Outbox retry UI + network restore polish

Implemented on PR16A/PR16B foundation. See [Messenger Outbox](MessengerOutbox.md) PR16C section for full behavior.

### Outbox status fields (unchanged schema)

| `status` | Meaning |
|----------|---------|
| `pending` | Ready or waiting for retry window |
| `sending` | Active network attempt |
| `failed` | Last attempt failed; may auto-retry per `nextRetryAt` |
| `sent` | Transitional before row delete |
| `cancelled` | User-cancelled (row deleted locally) |

### Pending/cancelled lifecycle (PR16C)

```text
pending/failed → user Delete → cancelPending
  → cancel in-memory task
  → remove optimistic bubble
  → deleteOutboxItem (+ pending media file for image)
  → no backend delete
```

Logout: `resetAllMessengerData()` clears all outbox + pending media rows and files.

### File map (PR16C additions)

| Path | Responsibility |
|------|----------------|
| `Shared/Views/Chats/OutgoingMessageStatus.swift` | UI labels + state helpers |
| `Shared/Views/Chats/MessengerOutboxErrorCode.swift` | Failure classification |
| `Shared/Components/Chat/ChatBubbleView.swift` | Unified outgoing status footer |
| `Shared/Views/Chats/ViewModels/ChatViewModel.swift` | Cancel pending vs confirmed delete |

### File map (PR16A additions)

| Path | Responsibility |
|------|----------------|
| `Core/Persistence/Messenger/Entities/LocalMessengerOutboxItem.swift` | SwiftData outbox entity |
| `Shared/Views/Chats/MessengerOutboxProcessor.swift` | Recovery, rehydrate, auto-retry |
| `Shared/Views/Chats/MessengerOutbox.swift` | Send queue + text persistence hooks |
| `JustTwoTests/MessengerOutboxTests.swift` | Outbox store + reconcile tests |
| `Shared/Views/Chats/MessengerDeltaSyncService.swift` | Delta → local cache writes |
| `JustTwoTests/MessengerConversationCacheTests.swift` | PR15B focused tests |
| `JustTwoTests/MessengerMessageCacheTests.swift` | PR15C focused tests |
| `JustTwoTests/MessengerLocalStoreTests.swift` | Store foundation tests |

### Tests

```bash
xcodebuild test -scheme JustTwo \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:JustTwoTests/MessengerMessageCacheTests \
  -only-testing:JustTwoTests/MessengerConversationCacheTests \
  -only-testing:JustTwoTests/MessengerLocalStoreTests \
  -only-testing:JustTwoTests/AppStartupCoordinatorTests
```

## Related docs

- [Startup loading and reset flow](StartupLoading.md)
- [Realtime](Realtime.md)
