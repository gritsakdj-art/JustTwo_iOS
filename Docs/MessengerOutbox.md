# Messenger Outbox

Persistent local send queue for messenger optimistic messages.

## Goal

Unsent outgoing messages must survive app kill, relaunch, and transient network failure, then retry without duplicate server messages via stable `clientMessageID` idempotency.

## PR16A scope (text)

| In scope | Out of scope (later PRs) |
|----------|--------------------------|
| Text outbox in SwiftData | Full background sync engine (PR16C) |
| Stable `clientMessageID` retry | Persistent sync cursor |
| Manual retry UI (existing failed bubble) | Polished retry-state UI (PR16C) |
| Limited auto-retry on chat open / network restore | |

## PR16B scope (image + composer preview)

| In scope | Out of scope |
|----------|--------------|
| Composer image preview before Send | Multiple image selection |
| Remove preview (X) without creating outbox | Image editing/cropping |
| Image + optional comment as **one** `kind=image` message | Polished failed/retry UI polish (PR16C) |
| Durable pending media files in Application Support | Full MessengerSyncEngine |
| `LocalMessengerPendingMedia` SwiftData metadata | Backend changes |
| Image outbox on PR16A lifecycle | Storing upload/download URLs |
| Upload session freshness on each retry | |
| Caption stored in outbox `body` for retry | |
| Rehydrate pending image bubbles after relaunch | |
| Reconcile by `clientMessageID` (no duplicates) | |
| Logout cleanup for outbox + pending media | |

### Composer preview (draft state)

Selecting an image in the photo picker is **draft-only**:

1. User taps attach → picks image.
2. Small preview appears in the composer/input area with an **X** remove button.
3. Text field stays editable for optional caption/comment.
4. **No** outbox row, **no** pending media file, **no** upload until Send.

Removing preview clears only the selected image; typed text remains.

### Send behavior

| Composer state | Result |
|----------------|--------|
| Text only | PR16A text outbox flow |
| Image only | One image outbox item, `body` empty / nil on wire |
| Image + text | One image outbox item; text sent as image `body` (caption) |

### Durable ordering (image Send)

```text
1. Generate stable clientMessageID + pendingMediaID
2. Encode image + write pending media file (Application Support)
3. Create LocalMessengerPendingMedia + LocalMessengerOutboxItem(kind=image)
4. Insert optimistic pending image bubble (with caption if any)
5. Clear composer preview + draft text
6. Register in-memory outbox + start upload/create pump
```

If persistence fails before step 4: composer is **not** cleared, no bubble, no upload.

## Model: `LocalMessengerOutboxItem`

SwiftData entity (`Core/Persistence/Messenger/Entities/LocalMessengerOutboxItem.swift`).

| Field | Purpose |
|-------|---------|
| `id` | Row UUID |
| `conversationID` | Target conversation |
| `clientMessageID` | Stable idempotency key (unique) |
| `kind` | `text` or `image` |
| `body` | Text message body **or** image caption for retry |
| `replyToMessageID` | Optional reply target |
| `pendingMediaID` | Links image outbox row to pending media (image only) |
| `status` | `pending` / `sending` / `failed` / `sent` / `cancelled` |
| `attemptCount` | Retry counter |
| `lastErrorCode` | Sanitized error category |
| `nextRetryAt` | Backoff schedule |
| `createdAt` / `updatedAt` / `lastAttemptAt` | Lifecycle timestamps |
| `serverMessageID` | Set on success before cleanup |

Domain layer uses `MessengerOutboxItemSnapshot` — SwiftUI does not depend on `@Model`.

## Model: `LocalMessengerPendingMedia` (PR16B)

Metadata only — **no image bytes**, no URLs, no absolute paths.

| Field | Purpose |
|-------|---------|
| `pendingMediaID` | Stable pending media key |
| `clientMessageID` | Links to outbox + optimistic bubble |
| `conversationID` | Target conversation |
| `localRelativePath` | Relative path under `MessengerPendingMedia/` |
| `contentType` / `byteSize` / `width` / `height` | Upload metadata |

Files live in `Application Support/JustTwo/MessengerPendingMedia/` with backup exclusion and `completeUntilFirstUserAuthentication` protection.

## Status lifecycle

```text
send tapped
  → pending (outbox row + pending media for image)
  → sending (network attempt started)
      ├─ success → delete outbox row + pending media, reconcile confirmed message
      └─ failure → failed (+ attemptCount, nextRetryAt); pending media kept

manual retry / auto-retry when due
  → pending → sending → ...
```

### Image retry pipeline

```text
pending image outbox item
  → read pending media file
  → request fresh upload session (uploadUrl ephemeral, never persisted)
  → PUT to Object Storage
  → create image message (stable clientMessageID + optional body/caption)
  → persist confirmed MessageDTO
  → reconcile optimistic bubble
  → delete outbox + pending media file
```

If upload succeeded but create-message failed: retry requests a **fresh** upload session (PR16B safe default).

### App kill / relaunch

On startup (`MessengerOutboxProcessor.recoverOnLaunch`):

- `sending` jobs older than **120s** → reset to `pending`
- Orphan pending media files pruned vs SwiftData metadata (counts only in diagnostics)

On chat open (`reconcileConversation`):

- Load outbox rows for conversation
- Skip rows already reconciled to confirmed cache/server message with same `clientMessageID`
- Rebuild missing pending/failed text or image bubbles from outbox + pending media
- Pump ready jobs when network is available

## Retry / backoff

`MessengerOutboxRetryPolicy`:

| Attempt | Delay |
|---------|-------|
| 1 | immediate / manual |
| 2 | +5s |
| 3 | +15s |
| 4+ | +60s (capped) |

`MessengerOutboxProcessor` selects `pending` / `failed` (due) / recovered `sending` text **and image** jobs, respects offline skip (`NetworkPathMonitor`), and pumps one in-flight send per conversation via `MessengerOutbox`.

## Idempotency / reconciliation

1. **Success REST response** — replace optimistic bubble, persist `MessageDTO`, delete outbox row + pending media.
2. **Duplicate `clientMessageID` from backend** — treat as success, reconcile, delete outbox row + pending media.
3. **Realtime/delta/REST arrives before retry** — reconciliation clears matching outbox row by `clientMessageID`.
4. **Never generate a new `clientMessageID` on retry.**
5. **Caption/comment preserved** in outbox `body` across retries.

## Components

| Component | Role |
|-----------|------|
| `MessengerLocalStore` | SwiftData CRUD for outbox + pending media rows |
| `MessengerPendingMediaStore` | Application Support file storage for outgoing pending images |
| `MessengerOutbox` | In-memory send queue + network attempts |
| `MessengerOutboxProcessor` | Recovery, rehydrate, auto-retry hooks |
| `MessageCacheStore` | Optimistic UI + merge/reconcile |
| `ChatViewModel` | Composer preview, Send, manual retry, chat-open reconcile |
| `MessageInputView` | Image preview strip + remove button |

## Privacy / security

| Allowed in SwiftData | Never stored / logged |
|----------------------|------------------------|
| Text/image caption in outbox `body` (retry required) | JWT / Authorization |
| IDs, status, attempt metadata | Signed `downloadUrl` / `uploadUrl` |
| Pending media relative path + dimensions | `X-Amz-Signature`, storage keys |
| | Image bytes in SwiftData |
| | Absolute local paths in diagnostics |
| | Caption/comment text in diagnostics export |

Diagnostics events (PR16B additions): `outboxImageComposerPreviewSelected`, `outboxImageComposerPreviewRemoved`, `outboxImageItemCreated`, `outboxPendingMediaStored`, `outboxImageUploadStarted/Succeeded/Failed`, `outboxImageCreateMessageStarted/Succeeded/Failed`, `outboxImageRehydrated`, `outboxPendingMediaCleared`, `outboxPendingMediaMissing`, `outboxImageRetryScheduled`.

## Logout cleanup

`AppStartupCoordinator.performReset()` → `MessengerLocalStore.resetAllMessengerData()` deletes all messenger entities including outbox + pending media metadata, and clears the pending media directory. In-memory `MessengerOutbox` is cleared separately.

## PR16C TODO

- Polished failed/retry UI states
- Broader auto-retry scheduler
- Optional move/copy pending file into confirmed media cache after success (if architecture allows without URL/storageKey leaks)

## Manual smoke

See PR16B report checklist in `ProjectStatus.md`.
