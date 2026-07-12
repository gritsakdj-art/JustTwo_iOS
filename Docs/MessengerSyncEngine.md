# Messenger Sync Engine (PR17)

Persistent global sync cursor and coordinated delta sync for messenger.

## Purpose

After PR17, messenger sync resumes from a **durable** `lastAppliedRevision` stored in SwiftData (`LocalMessengerSyncMetadata`). The in-memory `MessengerSyncStateStore` is hydrated from persistence on startup and updated only after successful local apply.

```text
REST remains authoritative.
Local DB provides immediate UI/cache/offline.
Realtime is foreground accelerator.
Delta sync repairs missed events and is the authoritative delivered-ACK coverage proof.
MessengerSyncEngine owns the persistent global cursor.
```

## Backend endpoints

| Endpoint | Role |
|----------|------|
| `GET /messenger/sync/state` | Server tip revision + server time |
| `GET /messenger/sync/events?afterRevision=&limit=&conversationID=` | Append-only delta pages |

Signed URLs in sync payloads are **runtime only** — never persisted.

## Persistent cursor (`LocalMessengerSyncMetadata`)

Single global row (`id = "global"`).

| Field | Purpose |
|-------|---------|
| `lastAppliedRevision` | Last successfully applied global revision |
| `lastSuccessfulSyncAt` | Last completed global sync |
| `lastFullRefreshAt` | Last REST baseline fallback |
| `lastAttemptedSyncAt` | Last sync attempt |
| `lastFailedAt` | Last failed attempt |
| `lastErrorCode` | Sanitized error category |
| `state` | Engine state machine raw value |
| `needsFullRefresh` | Invalid/gap cursor → REST baseline |
| `lastBootstrapAt` | Initial baseline timestamp |
| `lastKnownServerRevision` | Diagnostics / gap checks |
| `schemaVersion` | Messenger schema version |

Logout: `resetAllMessengerData()` clears metadata.

## State machine

```text
idle → bootstrapping → syncing → idle
syncing → failed → backoff → syncing
failed/backoff → needsFullRefresh → bootstrapping/full refresh
logout → reset
```

## Cursor advancement rules

Hard rule:

```text
Never advance lastAppliedRevision before events are successfully applied locally.
```

Order (PR20D2 — cursor + proven-safe boundary are one atomic save):

```text
fetch page → validate revision order → apply events → persist local message changes
→ commitAuthoritativeSyncPage(advancedRevision, safeBoundaries) [single ModelContext.save]
→ advance in-memory cursor → return committed boundaries → schedule delivered ACK → update UI
```

`MessengerLocalStore.commitAuthoritativeSyncPage` advances `lastAppliedRevision` and
monotonically merges the owner-scoped proven-safe delivery boundaries in a **single
`ModelContext.save()`**. If that save throws, neither the cursor nor the boundary is
durably updated, in-memory `appliedRevisions` for that page are rolled back, and the
sync page stays retryable. The delivered ACK is scheduled only after the commit returns,
so a proven-safe boundary is durable before any network ACK.

Conversation-filtered repair (`syncConversationRepair`) uses the same rule: a failed
`commitAuthoritativeSyncPage` emits `messengerDeliveryAckBoundaryPersistenceFailed`,
does **not** schedule ACK, rolls back page revisions, and remains retryable. Repair
does not advance the global cursor (`advancedRevision: nil`).

Delivered ACK rule (PR20D2):

```text
local apply alone is not enough
realtime / REST / pagination → request delta reconciliation
global delta page apply + atomic cursor/boundary commit → authoritativeSync evidence → delivered ACK
```

`ConversationDeliveryAckCoordinator` tracks applied local boundaries separately from proven-safe boundaries. Conversation previews and pagination pages never ACK directly.

### Durable proven-safe boundary recovery (PR20D2)

The highest authoritative proven-safe boundary `(createdAt, messageID)` for which a
backend delivered-ACK may still be required is persisted durably per
`ownerProfileID` + `conversationID` in `LocalMessengerPendingDeliveryReceipt`
(SwiftData). This survives process termination:

```text
delta commit persists cursor + boundary atomically
→ ACK network request fails or app is killed
→ persisted pending boundary survives
→ cold-start bootstrap loads owner boundaries and replays the ACK
→ backend duplicate ACK is a safe no-op (PR20D1)
→ successful ACK clears only the covered boundary (a strictly higher boundary is retained)
```

- Cold-start recovery runs in `AppStartupCoordinator` background warmup via
  `ConversationDeliveryAckCoordinator.bootstrapPersistedBoundaries(ownerProfileID:…)`;
  it does **not** require opening `ChatsView` / `PrivateChatView`.
- All persistence is account-scoped; logout wipes the records via
  `resetAllMessengerData()` and bumps the coordinator generation so stale
  callbacks and timers cannot ACK a prior owner with a new owner's JWT.
- A cleanup failure after a successful backend ACK never lowers in-memory
  confirmed state; the durable record may survive and a duplicate ACK after
  restart is a safe backend no-op that clears it on the next success.

## Global vs conversation-filtered sync

| Mode | Advances global cursor |
|------|------------------------|
| `MessengerSyncEngine.runGlobalSync` | Yes |
| `MessengerSyncEngine.repairConversation` | **No** |

Chat open uses conversation-filtered repair only.

## Delta page loop

- Page size: `MessengerSyncLimits.defaultEventPageSize` (200)
- Max pages per run: `MessengerSyncEngineLimits.maxPagesPerRun` (20)
- If more pages remain, engine schedules another global sync run
- Revision gap / out-of-order → `needsFullRefresh`

## Bootstrap / startup

1. Critical local warmup (cached UI) — non-blocking
2. `hydrateFromLocalStore()` — load persisted cursor
3. If no cursor or `needsFullRefresh`: bootstrap via `/sync/state` + REST refresh
4. If cursor exists: validate against server revision
5. Background `runGlobalSync(.bootstrap)`

Startup does **not** block `MainTabView`.

## Full refresh fallback

Triggered when:

- No sync metadata
- Cursor ahead of server revision
- Revision gap detected
- Repeated apply failure

Behavior:

- REST conversation/message refresh
- Re-bootstrap cursor from `/sync/state` after local apply
- Pending outbox **not** deleted

## Realtime / REST / outbox

| Source | Cursor owner | Delivered ACK coverage |
|--------|--------------|------------------------|
| Realtime | No — accelerator only | No direct ACK; requests delta reconciliation |
| REST refresh | No — authoritative baseline | No direct ACK; requests delta reconciliation |
| Pagination | No | Never ACKs directly |
| MessengerSyncEngine delta | Yes — global cursor | Yes, after atomic cursor + proven-safe boundary commit |
| Cold-start bootstrap | No | Replays durable proven-safe boundaries for the current owner |

Outbox reconciliation by `clientMessageID` unchanged (PR16). Full refresh does not wipe pending outgoing messages.

## Retry / backoff

| Failure | Delay |
|---------|-------|
| 1st | 5s |
| 2nd | 15s |
| 3rd+ | 60s |

Unauthorized: stop sync loop (session handles auth).

## Diagnostics (privacy-safe)

Events: `syncEngineStarted`, `syncBootstrapStarted/Succeeded/Failed`, `syncCursorAdvanced`, `syncDeltaPageApplied`, `syncNeedsFullRefresh`, `syncFullRefreshStarted/Succeeded/Failed`, `syncConversationRepairStarted/Applied`, `syncNetworkUnavailable`, `syncBackoffScheduled`, etc.

**PR18 export summary** (prepended to clipboard export): `presentationState`, `syncEngineState`, `lastAppliedRevision`, `lastSuccessfulSyncAt`, outbox counts, `conversationCacheAvailable`. See [Messenger Offline UX](MessengerOfflineUX.md).

Forbidden: message body, caption, JWT, signed URLs, storage keys, absolute paths.

## User-facing sync mapping (PR18)

| Engine state | User-facing (when cache visible) |
| --- | --- |
| `syncing` / `bootstrapping` | Refreshing… (subtle strip) |
| `failed` / `needsFullRefresh` | Couldn't refresh. Saved data is still available. |
| `idle` | Normal / optional “Updated just now” |

## Known limitations / PR20

- Backend retention/metrics not implemented (PR20)
- Realtime does not advance persistent cursor (by design)
- Durable persisted delivered-ACK recovery boundary shipped in PR20D2
  (`LocalMessengerPendingDeliveryReceipt`, atomic cursor+boundary commit, cold-start bootstrap)
- Background remote-notification wake + bounded sync shipped in PR20D3B
  (`MessengerBackgroundSyncCoordinator`, `runGlobalSyncForBackground`, best-effort ACK flush).
  Batch/cohort coalescing (late pushes form the next batch), single absolute deadline,
  durable ACK bootstrap before flush, foreground-sync join — see
  [MessengerBackgroundSync.md](MessengerBackgroundSync.md)
- SwiftData schema bumped to v6 (additive entity); container has a destructive
  recreate fallback on load failure — an upgrade smoke test is required
- Manual smoke required before release (status: NOT RUN)

## Components

| Component | Role |
|-----------|------|
| `MessengerSyncEngine` | Orchestration, persistence, lifecycle |
| `MessengerDeltaSyncService` | Fetch + apply delta events |
| `MessengerSyncStateStore` | Runtime cursor + dedup |
| `MessengerLocalStore` | SwiftData metadata CRUD |
| `MessengerSyncService` | Network API |
