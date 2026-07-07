# Messenger Local Storage (PR15A)

Foundation for on-device messenger persistence using SwiftData. This PR adds schema, mapping, store API, logout reset wiring, and tests. UI and sync pipelines still read from in-memory caches; local reads are disabled behind a feature flag.

## Goals

1. Define a privacy-safe SwiftData schema for conversations, messages, attachments, reaction aggregates, receipts, and sync metadata.
2. Provide a typed store API (`MessengerLocalStore`) with DTO → entity mapping and snapshot read models.
3. Reset local messenger data on logout without racing a fast re-login.
4. Add diagnostics and unit tests without changing current user-visible behavior.

## Non-goals (PR15A)

- UI does **not** read from the local DB yet (`MessengerLocalStorageFeatureFlags.isLocalReadEnabled = false`).
- Delta sync / realtime handlers do **not** write to the local DB yet.
- Signed `downloadUrl` / `uploadUrl` values are **not** persisted.
- PR14B in-memory delta cursor behavior is unchanged.

## Architecture

```text
JustTwoApp.sharedModelContainer (SwiftData)
  └─ MessengerLocalStore.configureShared(modelContainer:)
        └─ MessengerLocalStore (@MainActor facade)
              ├─ sessionGeneration + isResetInFlight guards
              └─ SwiftDataMessengerLocalStore (@MainActor)
                    └─ ModelContext(modelContainer) per operation
```

### File map

| Path | Responsibility |
|------|----------------|
| `Core/Persistence/Messenger/MessengerPersistence.swift` | Schema, `ModelContainer` factory, entity type list |
| `Core/Persistence/Messenger/Entities/*.swift` | SwiftData `@Model` entities |
| `Core/Persistence/Messenger/LocalMessengerSnapshots.swift` | Sendable read snapshots returned by the store |
| `Core/Persistence/Messenger/MessengerLocalMapping.swift` | DTO ↔ entity mapping, privacy filtering |
| `Core/Persistence/Messenger/MessengerLocalStoreProtocol.swift` | `@MainActor` store contract |
| `Core/Persistence/Messenger/MessengerLocalStore.swift` | Shared facade, session guards, diagnostics |
| `Core/Persistence/Messenger/SwiftDataMessengerLocalStore.swift` | SwiftData implementation |
| `JustTwoApp.swift` | Registers messenger models in app `ModelContainer` |
| `JustTwoTests/MessengerLocalStoreTests.swift` | Store mapping, upsert, reset, guard tests |

## SwiftData schema

Six messenger entities (plus existing template `Item.self` in the app container):

| Entity | Key fields | Notes |
|--------|------------|-------|
| `LocalMessengerConversation` | `id`, participant preview, `lastMessageAt`, `unreadCount` | No signed photo URLs |
| `LocalMessengerMessage` | `id`, `clientMessageID`, tombstone fields, `localState` | Supports client/server ID reconciliation |
| `LocalMessengerAttachment` | metadata only | `localCacheKey`, `downloadURLExpiresAt`; no signed URL |
| `LocalMessengerReactionAggregate` | `id = messageID:emoji`, `count`, `reactedByMe` | Matches backend aggregate DTO |
| `LocalMessengerReceipt` | per-profile delivery/read watermarks | |
| `LocalMessengerSyncMetadata` | `lastAppliedRevision`, `schemaVersion` | Global row id `global` |

`MessengerPersistence.schemaVersion = 1`.

## Thread / actor confinement

- `MessengerLocalStore`, `SwiftDataMessengerLocalStore`, and `MessengerLocalStoreProtocol` are `@MainActor`.
- `ModelContainer` is created once in `JustTwoApp` (disk-backed) or via `MessengerPersistence.makeModelContainer(inMemoryOnly:)` in tests.
- Each store operation creates a **fresh** `ModelContext` and runs fetch/mutate/save synchronously on MainActor with no `await` in the middle.
- Arbitrary `Task` callers are serialized by MainActor; concurrent use of the same `ModelContext` does not occur.

## Store API

Public write/read entry points on `MessengerLocalStore.shared`:

- `resetAllMessengerData()`
- `upsertConversations(_:)`
- `fetchLocalConversations()`
- `upsertMessages(_:conversationID:)`
- `fetchLocalMessages(conversationID:limit:before:)`
- `markMessageDeleted(messageID:deletedAt:)`
- `upsertReactions(from:)`
- `applyReceipt(_:)`
- `upsertSyncMetadata(_:)` / `fetchSyncMetadata()`

Errors:

| Error | Meaning |
|-------|---------|
| `storeUnavailable` | Reset in flight; reads/writes rejected |
| `staleSession` | Operation started before reset and finished after generation bump |
| `conversationMismatch` | Message upsert batch targets wrong conversation |

## Logout reset and race hardening

Problem: fire-and-forget async DB reset could overlap with a very fast re-login.

Solution (both layers):

1. **Awaited reset path**
   - `SessionStore.clearSession()` → `AppStartupCoordinator.scheduleLogoutReset()`
   - `runCriticalWarmup()` → `await waitForLogoutReset()` before new-session warmup
   - `performReset()` → `try await MessengerLocalStore.shared.resetAllMessengerData()`

2. **Session generation guard** on `MessengerLocalStore`
   - `sessionGeneration` increments at reset start
   - `isResetInFlight` blocks concurrent access
   - stale reset completions are ignored if superseded

```text
logout → scheduleLogoutReset (Task @MainActor)
              └─ performReset → await resetAllMessengerData()

next login → runCriticalWarmup
              └─ await waitForLogoutReset()   // blocks until logout reset finishes
              └─ ... critical loaders ...
```

## Feature flag

```swift
enum MessengerLocalStorageFeatureFlags {
    static let isLocalReadEnabled = false  // PR15B
}
```

## Diagnostics

Privacy-safe events in `MessengerDiagnostics`:

- `messengerLocalStoreInitialized`
- `messengerLocalStoreResetStarted` / `ResetSucceeded` / `ResetFailed`
- `messengerLocalConversationUpserted`
- `messengerLocalMessagesUpserted`
- `messengerLocalMessageDeleted`
- `messengerLocalReceiptApplied`
- `messengerLocalSyncMetadataUpdated`
- `messengerLocalMappingFailed`

Metadata avoids signed URLs, tokens, and message bodies.

## Tests

`JustTwoTests/MessengerLocalStoreTests.swift` — mapping, upsert idempotency, tombstones, reactions, receipts, sync metadata monotonicity, reset, in-flight guard, session generation.

`JustTwoTests/AppStartupCoordinatorTests.swift` — `waitForLogoutResetBlocksUntilLocalStoreIsCleared`.

Run:

```bash
xcodebuild test -scheme JustTwo \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:JustTwoTests/MessengerLocalStoreTests \
  -only-testing:JustTwoTests/AppStartupCoordinatorTests
```

## Next steps (PR15B+)

- Wire delta sync / conversation list writes into `MessengerLocalStore`.
- Flip `isLocalReadEnabled` and serve conversation list from local snapshots.
- Consider `ModelActor` if sync writes move off MainActor at volume.

## Related docs

- [Startup loading and reset flow](StartupLoading.md)
