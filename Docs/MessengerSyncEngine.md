# Messenger Sync Engine (PR17)

Persistent global sync cursor and coordinated delta sync for messenger.

## Purpose

After PR17, messenger sync resumes from a **durable** `lastAppliedRevision` stored in SwiftData (`LocalMessengerSyncMetadata`). The in-memory `MessengerSyncStateStore` is hydrated from persistence on startup and updated only after successful local apply.

```text
REST remains authoritative.
Local DB provides immediate UI/cache/offline.
Realtime is foreground accelerator.
Delta sync repairs missed events.
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

Order:

```text
fetch page → validate revision order → apply events → persist local changes
→ advance in-memory cursor → persist lastAppliedRevision → update UI
```

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

| Source | Cursor owner |
|--------|----------------|
| Realtime | No — accelerator only |
| REST refresh | No — authoritative baseline |
| MessengerSyncEngine delta | Yes — global cursor |

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

Forbidden: message body, caption, JWT, signed URLs, storage keys, absolute paths.

## Known limitations / PR20

- Backend retention/metrics not implemented (PR20)
- Realtime does not advance persistent cursor (by design)
- Manual smoke required before release

## Components

| Component | Role |
|-----------|------|
| `MessengerSyncEngine` | Orchestration, persistence, lifecycle |
| `MessengerDeltaSyncService` | Fetch + apply delta events |
| `MessengerSyncStateStore` | Runtime cursor + dedup |
| `MessengerLocalStore` | SwiftData metadata CRUD |
| `MessengerSyncService` | Network API |
