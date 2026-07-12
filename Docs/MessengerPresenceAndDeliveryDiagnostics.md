# Messenger Presence And Delivery Diagnostics (PR20A / PR20C / PR20D2)

Audit and stabilization notes for realtime presence and delivery acknowledgements.

**Status:** PR20A + PR20C implemented on feature branches. PR20D2 iOS delivery ACK coverage hardening implemented on `ios-messenger-delivery-acks-pr20d2`. Manual smoke **NOT RUN**.

Related roadmap:

| PR | Scope |
|----|--------|
| **PR20A** | Diagnostics, local defect fixes, tests |
| PR20B | Backend persisted `lastSeenAt` / presence summary |
| **PR20C** (this doc, iOS) | Last-seen UI, REST/sync/cache reconciliation, formatter |
| PR20D1 | Backend delivery receipt hardening |
| PR20D2 | iOS background/foreground delivery acknowledgements |

---

## Backend presence summary (PR20B contract)

Conversation-authorized DTOs include optional profile `presence`:

```json
{
  "presence": {
    "isOnline": false,
    "lastSeenAt": "2026-07-10T12:00:00Z"
  }
}
```

`lastSeenAt` is always present in JSON and may be `null`. Sources: `GET /conversations`, read/delivered responses, invite accept, live rebuilt sync `ConversationDTO`, and realtime `presence.changed` (`isOnline` + `lastSeenAt`).

Not present on: invite preview, profile/me, message DTO, push payload, persisted sync event rows.

---

## Definitions

### Online

User is **online** if the backend realtime presence registry contains at least one active authenticated WebSocket for that user's profile.

Not defined by: last message time, REST activity, push delivery, or client guesswork.

### Sent

Backend accepted and persisted the message. UI: one checkmark.

### Delivered

At least one recipient app explicitly acknowledged receipt via `PATCH /conversations/:id/delivered` after applying the message in the messenger data layer. UI: two checkmarks.

**Not** delivered when:

- APNs accepted a push
- Push was displayed
- User opened the conversation (that is **read**)

### Read

User opened the relevant conversation and the message entered the read boundary. UI: highlighted/colored two checkmarks.

`read` may monotonically advance `delivered` on the backend; `delivered` must not wait for `read`.

---

## Architecture map

### Backend presence

```text
WebSocket /ws/realtime
  → JWT auth (Bearer preferred; ?token= fallback)
  → RealtimeConnectionRegistry.add (sync)
  → connection.ready
  → RealtimePresenceService.registerConnection (async)
       guard: connection still in connection registry
       → RealtimePresenceRegistry (profileID → connectionIDs)
       → first socket: presence.changed online
       → additional sockets: no duplicate online
  → onClose
       → RealtimeConnectionRegistry.remove (sync, idempotent)
       → RealtimePresenceService.unregisterConnection (async)
            → last socket: presence.changed offline
            → intermediate: no offline
```

Audience: other active conversation participants (blocks excluded). Presence does **not** require conversation subscription.

### iOS presence (PR20C)

```text
REST GET /conversations / read / delivered / invite accept
  → PresenceStore.applySnapshot source=rest

Sync live ConversationDTO (rebuilt server-side, not historical revision)
  → PresenceStore.applySnapshot source=sync

SwiftData cache hydrate
  → otherParticipantLastSeenAt only
  → PresenceStore source=cache (never marks online)

RealtimeClient
  → presence.changed (isOnline + lastSeenAt) → source=realtime (authoritative per **connection epoch**)
  → typing.started → typingHint map (TTL 15s, display-only; separate from isOnline)
  → typing.stopped / TTL / realtime offline → clear hint
  → reconnect → new socket creates immutable RealtimeConnectionContext (connectionID + epoch + sessionGeneration)
  → stale events from old socket dropped in RealtimeClient before route; coordinator double-checks

Reconciliation:
  1. realtime authoritative only for profiles observed in **current connection epoch**
  2. REST/sync in current epoch may set isOnline until realtime observation in that epoch
  3. REST/sync started in a **stale connection epoch** (late callback after reconnect) ignores isOnline; may still advance lastSeenAt
  4. cache never confirms online
  5. logout / explicit disconnect clears account-scoped presence memory (monotonic lastSeenAt in memory cleared; persisted cache lastSeenAt remains)

UI:
  PrivateChatView header + conversation row → shared PresenceStore
  LastSeenStatusFormatter (Calendar today/yesterday, RU/EN, nil → no text)
```

#### Source priority (`isOnline`)

| Priority | Source | Notes |
|----------|--------|-------|
| 1 | `.realtime` | Authoritative after observation in **current connection epoch** |
| 2 | `.rest` / `.sync` | Before realtime in epoch; after reconnect can correct missed offline |
| 3 | `.typingHint` | Display-only ephemeral map; does not set isOnline |
| 4 | `.preserved` | Reconnect TTL 90s (provisional online) |
| 5 | `.cache` | Never sets online |

#### `lastSeenAt`

Monotonic `max(current, incoming)` across realtime, REST, sync, cache. Cleared on logout/account switch.

#### Cache policy

SwiftData `LocalMessengerConversation.otherParticipantLastSeenAt` persisted. **Never** persist `isOnline`, typing hints, preserved state, or realtime observation metadata.

#### Offline device semantics

Local network offline does not mark remote peers offline. Cached `lastSeenAt` may display; cached online is not shown.

#### Deep link / chat open

Push routing refreshes conversation list when `ChatConversationPreview` missing; presence appears after cache/REST/realtime hydration. No `GET /conversations/:id` endpoint — gap documented for future PR.

#### Diagnostics (privacy-safe)

| Event | When |
|-------|------|
| `presenceSnapshotReceived` | REST/sync conversation snapshot with presence |
| `presenceSnapshotApplied` | Store accepted snapshot |
| `presenceSnapshotIgnoredRealtimeNewer` | REST/sync isOnline ignored; may still advance lastSeen |
| `presenceRealtimeEpochIgnored` | Stale realtime callback from previous connection epoch |
| `realtimeTransportEpochIgnored` | Stale socket transport event dropped before routing |
| `presenceStaleRequestIgnored` | REST/sync callback from stale connection epoch |
| `presencePayloadStatusConflict` | isOnline/status conflict; isOnline applied |
| `presenceCacheWriteIgnored` | Stale session/account cache write skipped |
| `presenceLastSeenAdvanced` / `presenceLastSeenIgnoredOlder` | Monotonic lastSeenAt |
| `presenceCacheHydrated` / `presenceCachePersisted` | Cache read/write of lastSeenAt |
| `presenceDisplayStateChanged` | Debug-only semantic UI transition |

Fields: truncated `profileID`, `source`, `incomingOnline`, `previousOnline`, `hasLastSeenAt`, `didAdvanceLastSeen`, `sessionGeneration`, `realtimeConnectionEpoch`, `reason`. Never log displayName, message body, JWT, raw payloads.

#### Backend-authoritative presence vs typing hint

| Kind | Source | Persisted? | TTL | Cleared by |
|------|--------|------------|-----|------------|
| Backend-authoritative | `presence.changed` → `.realtime` | No (memory only) | None | offline event, logout, explicit disconnect |
| Typing activity hint | `typing.started` → `.typingHint` | No | 15s | `typing.stopped`, TTL, realtime offline, logout |
| Provisional reconnect | `.preserved` | No | 90s | realtime event, TTL, logout |

Typing hint is **not** authoritative presence and is never written to SwiftData/cache.

#### Reconnect freshness (bounded, not complete)

Preserving presence avoids false offline while typing after short reconnects. Entries are remapped to `.preserved` with a 90s TTL. This is **provisional**, not a new backend observation. Missed offline during long disconnect / backend restart can leave stale online until TTL, REST/sync snapshot, or next realtime event.

### Backend register sequence (close-before-publish safe)

```text
1. ConnectionRegistry check
2. Profile lookup (await)
3. ConnectionRegistry re-check
4. PresenceRegistry.register(connectionID)
5. optional test barrier
6. Post-register live check (connection + presence contains connectionID)
7. Audience resolve (await)
8. Final live check
9. presence.changed online publish
```

Rollback unregisters **only that connectionID** (does not remove a newer socket for the same profile). If rollback yields last-socket offline and close-path has not published yet, rollback publishes offline once.

### Delivery

```text
Sender → message persisted → message.created + optional APNs
Recipient applies message via:
  realtime | sync delta | REST list/fetch | chat open
  → local apply/dedup in messenger layer completes
  → ConversationDeliveryAckCoordinator (monotonic boundary, coalescing, retry)
  → PATCH /conversations/:id/delivered
Backend advances lastDeliveredAt if newer
  → conversation.delivered realtime + sync event (if advanced)
Sender UI applies deliveryStatus / conversation.delivered
```

Active chat: `markDelivered` then `markRead` independently — delivered does not wait for read success. Backend `markRead` also advances delivered (read implies delivered).

Delivery ACK is scheduled only after the inbound message has been applied to the messenger data layer, the local store write has succeeded, and the source provides contiguous coverage evidence. Foreground chat visibility is not required for delivered; read still requires opening/using the chat.

PR20D2 separates:

- **Applied local boundary:** highest inbound message seen locally in memory/cache.
- **Proven safe boundary:** highest inbound boundary backed by authoritative coverage evidence.
- **Pending / in-flight / confirmed:** network ACK lifecycle after a boundary is proven safe.

Realtime, REST pages, pagination, and conversation previews can advance the applied local boundary but cannot directly call `PATCH /delivered`. They defer via diagnostics (`messengerDeliveryAckDeferredCoverage`) and rely on delta reconciliation. Authoritative global delta sync is the primary coverage proof.

**Durable proven-safe boundary recovery (PR20D2):** the highest proven-safe boundary is persisted durably and account-scoped (`LocalMessengerPendingDeliveryReceipt`, key `ownerProfileID|conversationID`). The sync cursor advance and the boundary persist happen in a single atomic `ModelContext.save()` (`commitAuthoritativeSyncPage`), and the network ACK is scheduled only after that commit returns. On cold start, `ConversationDeliveryAckCoordinator.bootstrapPersistedBoundaries(ownerProfileID:…)` reloads the current owner's boundaries and replays the ACK without opening a chat. A successful backend ACK clears only the covered boundary (a strictly higher persisted boundary is retained and ACKed next). Backend duplicate ACK is a safe no-op (PR20D1), so replay after termination is safe.

Current iOS apply paths:

```text
realtime message.created
  → decode
  → memory apply / dedup
  → SwiftData message persist
  → request coalesced delta reconciliation
  → no direct delivery ACK

delta sync message.created
  → decode
  → memory apply / dedup
  → SwiftData message persist
  → atomic commit: cursor advance + proven-safe boundary persist (one save)
  → authoritative delivery ACK scheduled only after successful commit

cold-start bootstrap (background warmup, no chat open)
  → load durable pending boundaries for current owner
  → re-check session generation + owner after await
  → replay delivered ACK via existing pipeline
  → successful ACK clears only the covered boundary

REST messages refresh / startup preload / repair
  → decode
  → merge / dedup
  → SwiftData message persist
  → request coalesced delta reconciliation
  → no direct delivery ACK

conversation list REST refresh
  → decode
  → preview apply
  → SwiftData conversation + last-message snapshot persist
  → no delivery ACK candidate; preview is not message data-layer apply

message fetch after list/cold-start/reconnect repair
  → decode
  → merge / dedup
  → SwiftData message + attachment metadata persist
  → request coalesced delta reconciliation
  → no direct delivery ACK

pagination / older messages
  → decode
  → merge / dedup
  → SwiftData message + attachment metadata persist
  → no delivery ACK candidate

background remote notification
  → parse wake hint (event == message.created)
  → bounded session recovery
  → MessengerSyncEngine.runGlobalSyncForBackground (authoritative PR20D2 pipeline)
  → proven-safe boundary persisted durably
  → best-effort delivered ACK flush
  → UIBackgroundFetchResult exactly once
  → push messageID is never ACKed directly
```

Background handling is best-effort and depends on iOS launching the app for a remote notification with the required APNs background delivery conditions. APNs acceptance, notification display, and notification tap are not delivery evidence. Force-quit can prevent background execution. See [MessengerBackgroundSync.md](MessengerBackgroundSync.md).

Manual smoke checklist:

```text
1. A sends to B while B app is foreground on conversation list: B applies realtime/REST locally, delta reconciliation proves coverage, then B ACKs delivered without opening chat.
2. A sends to B while B is in another chat: B ACKs delivered only after authoritative delta proof; read only advances if B opens A's chat.
3. B receives realtime message while local persistence is forced to fail: no delivered ACK; diagnostic messengerDeliveryAckApplyFailed appears.
4. B is offline during ACK send: pending ACK retries after network restore / app foreground.
5. B logs out or switches account before retry: pending ACK is cleared and stale retry is ignored.
6. B receives push in background: wake hint triggers bounded sync; delivered ACK only after authoritative delta proof (not from payload messageID).
7. Durable recovery: B applies an inbound message via delta sync (boundary persisted), network is disabled before ACK, B is force-quit, network restored, B relaunched → pending boundary loads on cold start without opening the chat, ACK replays, A sees delivered. A subsequent relaunch after successful cleanup issues no ACK.
8. Higher boundary: ACK C in flight, sync applies D, C succeeds → D remains pending and is ACKed next.
9. Account switch: B has a pending ACK, logout, login D → B's ACK never sent with D's JWT; diagnostics contain no JWT/content.
10. Upgrade existing install (schema v5 → v6): store opens without destructive recreation, conversations/messages/outbox/media survive, new pending-boundary storage works.
```

---

## Diagnostic events

### Backend (structured Logger metadata)

| Event | Purpose |
|-------|---------|
| `realtime.first_connection` | 0→1 sockets, will publish online |
| `realtime.additional_connection` | N→N+1, no online publish |
| `realtime.intermediate_disconnect` | unregister without offline |
| `realtime.last_disconnect` | 1→0, will publish offline |
| `realtime.presence_online_published` | fanout online |
| `realtime.presence_offline_published` | fanout offline |
| `realtime.socket_register_skipped_stale` | closed before/during register |
| `realtime.socket_register_skipped_no_profile` | no Profile for user |
| `realtime.socket_register_rolled_back` | closed after register before publish |
| `realtime.registry_state_mismatch` | unexpected transition |
| `delivery.ack_received` | PATCH delivered received |
| `delivery.boundary_advanced` | lastDeliveredAt moved |
| `delivery.noop` | duplicate/older ack |
| `delivery.realtime_published` | conversation.delivered sent |

IDs are truncated (8 hex chars + `...`). No JWT, bodies, or signed URLs.

### iOS (MessengerDiagnostics ring buffer)

| Event | Purpose |
|-------|---------|
| `realtimeConnectRequested` | connect start |
| `realtimeConnectionReady` | connection.ready handled |
| `realtimeDisconnected` | explicit disconnect |
| `realtimeReconnectScheduled` | backoff scheduled |
| `presenceEventReceived` | presence.changed received |
| `presenceStateApplied` / `presenceStateIgnored` | store update outcome |
| `presenceCacheLoaded` | reconnect preserve note |
| `messengerDeliveryAckDeferredCoverage` | local apply observed but source lacks coverage proof |
| `messengerDeliveryAckScheduled` | proven safe boundary scheduled |
| `messengerDeliveryAckBoundaryPersisted` | proven-safe boundary durably committed with cursor |
| `messengerDeliveryAckBoundaryPersistenceFailed` | atomic cursor+boundary commit failed (page retryable) |
| `messengerDeliveryAckBootstrapStarted` / `…Loaded` | cold-start recovery started / owner boundaries loaded |
| `messengerDeliveryAckBootstrapScheduled` | recovered boundary re-scheduled for ACK |
| `messengerDeliveryAckBootstrapIgnoredStaleSession` | bootstrap ignored (generation changed / already in flight / load failed) |
| `messengerDeliveryAckPendingCleared` | durable boundary cleared after confirmed ACK / reset |
| `messengerDeliveryAckPendingRetainedHigherBoundary` | higher persisted boundary retained over lower ACK |
| `messengerDeliveryAckPendingCleanupFailed` | post-ACK durable cleanup failed (record may survive; duplicate replay is a safe no-op) |
| `messengerDeliveryAckIgnoredWrongOwner` | boundary owner mismatched current session owner |
| `messengerBackgroundPushReceived` / `…Ignored` / `…Malformed` | background wake hint received / rejected |
| `messengerBackgroundSyncQueued` / `…Started` / `…Coalesced` / `…TrailingRequested` | background sync lifecycle |
| `messengerBackgroundSyncNextBatchQueued` | late push (after trailing started) assigned to the next batch cohort |
| `messengerBackgroundSyncBatchStarted` / `…BatchExpired` | batch drain start / next batch expired before it could run |
| `messengerBackgroundSyncCompleted` / `…Failed` / `…Expired` | background sync outcome |
| `messengerBackgroundAckFlushStarted` / `…Completed` / `…Deferred` | bounded ACK flush |
| `messengerBackgroundCompletionCalled` / `…DuplicateIgnored` | exactly-once fetch completion |
| `messengerBackgroundSessionStale` / `…DependenciesUnavailable` | session/generation or readiness guards |
| `deliveryMessageObserved` | legacy inbound message observation |
| `deliveryAckScheduled` | legacy ack path entered |
| existing `deliveredAckSent` / `Skipped` / `Failed` | REST ack result |

Fields are privacy-safe: truncated conversation/message IDs, `count`, `reason`, `sessionGeneration`, `source`, `errorCategory`. Never: JWT/Authorization/Bearer, message body, caption, raw payload, device token, signed URL, storage key, absolute path, owner email/display name. The durable `key` is never logged in full.

---

## Known limitations (product / platform)

1. **Background WebSocket:** default `messagesEnabled == false` disconnects WS in background → peer appears offline. Product policy undecided.
2. **Background push is best-effort:** PR20D3B wake sync is not guaranteed (force quit, throttling, no execution budget). Foreground/cold-start fallback remains required.
3. **Coverage gate:** delivered ACK requires authoritative delta proof or a durably persisted safe boundary recovery (PR20D2 cold-start bootstrap); local max message alone is not enough.
4. **Presence not in REST/sync:** preserved reconnect state is provisional (90s TTL); full freshness is **PR20B/C**.
5. **Single-instance in-memory presence:** no multi-node registry.
6. **`lastSeenAt` ephemeral:** disconnect-time only; not persisted (PR20B).
7. **Manual smoke NOT RUN.**

---

## Root cause summary (PR20A)

### Online mismatch while peer is typing

**Proven contributors:**

1. Header UI prefers typing subtitle over “Online” (by design).
2. Presence wiped on reconnect before PR20A → online gap until next event.
3. Typing did not update `PresenceStore` → typing without green/online state.
4. Background WS disconnect clears presence.

**Fixed in PR20A:** typing online hint; preserve presence across reconnect; diagnostics.

**NOT PROVEN as sole cause:** backend ghost-online race (fixed defensively); REST overwrite (presence not in REST).

### Delivered only after recipient opens app

**Proven:**

1. Every ack path gated on foreground `.active`.
2. Sync delta applied messages **without** scheduling ack (fixed in PR20A for foreground sync, hardened in PR20D2 with coverage evidence).
3. Background push wake (PR20D3B) schedules delivered ACK only through authoritative delta sync — never from push `messageID`.
4. Chat open is **not** the only trigger; inactive realtime/REST can trigger delta reconciliation, but direct delivered ACK requires authoritative proof.

**Shipped in PR20D2:** durable persisted proven-safe boundary recovery with atomic cursor+boundary commit and cold-start bootstrap.

**Shipped in PR20D3B:** best-effort background wake sync + bounded ACK flush — see [MessengerBackgroundSync.md](MessengerBackgroundSync.md).

---

## Reproduction matrix (manual smoke)

See PR20A report section 13. Status: **NOT RUN**.

---

## Privacy

Do not log: JWT, Authorization, WebSocket query tokens, message body/caption, signed URLs, full push payloads, absolute local paths.

Safe: truncated IDs, counts, durations, reasons, generation, scene/network state.
