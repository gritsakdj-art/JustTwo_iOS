# Messenger Outbox

Persistent local send queue for messenger optimistic messages.

## Goal

Unsent outgoing messages must survive app kill, relaunch, and transient network failure, then retry without duplicate server messages via stable `clientMessageID` idempotency.

## PR16A scope (text only)

| In scope | Out of scope (later PRs) |
|----------|--------------------------|
| Text outbox in SwiftData | Persistent image outbox (PR16B) |
| Stable `clientMessageID` retry | Pending media files on disk |
| Manual retry UI (existing failed bubble) | Upload retry pipeline |
| Limited auto-retry on chat open / network restore | Full background sync engine (PR16C) |
| Reconciliation with REST/realtime/delta | Persistent sync cursor promotion |

## Model: `LocalMessengerOutboxItem`

SwiftData entity (`Core/Persistence/Messenger/Entities/LocalMessengerOutboxItem.swift`).

| Field | Purpose |
|-------|---------|
| `id` | Row UUID |
| `conversationID` | Target conversation |
| `clientMessageID` | Stable idempotency key (unique) |
| `kind` | `text` in PR16A |
| `body` | Message text for resend (**stored locally only**) |
| `replyToMessageID` | Optional reply target |
| `status` | `pending` / `sending` / `failed` / `sent` / `cancelled` |
| `attemptCount` | Retry counter |
| `lastErrorCode` | Sanitized error category |
| `nextRetryAt` | Backoff schedule |
| `createdAt` / `updatedAt` / `lastAttemptAt` | Lifecycle timestamps |
| `serverMessageID` | Set on success before cleanup |

Domain layer uses `MessengerOutboxItemSnapshot` — SwiftUI does not depend on `@Model`.

## Status lifecycle

```text
send tapped
  → pending (outbox row created)
  → sending (network attempt started)
      ├─ success → delete outbox row, reconcile confirmed message
      └─ failure → failed (+ attemptCount, nextRetryAt)

manual retry / auto-retry when due
  → pending → sending → ...

logout / resetAllMessengerData
  → outbox cleared
```

### App kill / relaunch

On startup (`MessengerOutboxProcessor.recoverOnLaunch`):

- `sending` jobs with `lastAttemptAt` / `updatedAt` older than **120s** → reset to `pending`

On chat open (`reconcileConversation`):

- Load outbox rows for conversation
- Skip rows already reconciled to confirmed cache/server message with same `clientMessageID`
- Insert missing pending/failed bubbles into `MessageCacheStore`
- Rehydrate in-memory `MessengerOutbox` queue
- Pump ready text jobs when network is available

## Retry / backoff

`MessengerOutboxRetryPolicy`:

| Attempt | Delay |
|---------|-------|
| 1 | immediate / manual |
| 2 | +5s |
| 3 | +15s |
| 4+ | +60s (capped) |

`MessengerOutboxProcessor` selects `pending` / `failed` (due) / recovered `sending` text jobs, respects offline skip (`NetworkPathMonitor`), and pumps one in-flight send per conversation via `MessengerOutbox`.

## Idempotency / reconciliation

1. **Success REST response** — replace optimistic bubble, persist `MessageDTO`, delete outbox row.
2. **Duplicate `clientMessageID` from backend** — treat as success, reconcile, delete outbox row.
3. **Realtime/delta/REST arrives before retry** — `MessageCacheStore` reconciliation clears matching outbox row by `clientMessageID`.
4. **Never generate a new `clientMessageID` on retry.**

## Components

| Component | Role |
|-----------|------|
| `MessengerLocalStore` | SwiftData CRUD for outbox rows |
| `MessengerOutbox` | In-memory send queue + network attempts (text persisted) |
| `MessengerOutboxProcessor` | Recovery, rehydrate, auto-retry hooks |
| `MessageCacheStore` | Optimistic UI + merge/reconcile |
| `ChatViewModel` | Send, manual retry, chat-open reconcile |

## Privacy / security

| Allowed in SwiftData outbox | Never stored / logged |
|-----------------------------|------------------------|
| Text `body` (resend required) | JWT / Authorization |
| IDs, status, attempt metadata | Signed `downloadUrl` / `uploadUrl` |
| | `X-Amz-Signature`, storage keys |
| | Image bytes |
| | Message `body` in diagnostics export |

Diagnostics events: `outboxItemCreated`, `outboxSendStarted`, `outboxSendSucceeded`, `outboxSendFailed`, `outboxRetryScheduled`, `outboxManualRetry`, `outboxItemCleared`, `outboxReset`, `outboxRehydrated`.

## Logout cleanup

`AppStartupCoordinator.performReset()` → `MessengerLocalStore.resetAllMessengerData()` deletes all messenger entities including outbox rows. In-memory `MessengerOutbox` is cleared separately.

## PR16B / PR16C TODO

- PR16B: persistent image outbox + temp file durability
- PR16C: polished network-return retry scheduler, broader auto-retry policy, upload retry integration

## Manual smoke

See PR16A report checklist in implementation notes / `ProjectStatus.md`.
