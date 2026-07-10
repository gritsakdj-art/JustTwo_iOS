# Messenger Presence And Delivery Diagnostics (PR20A / PR20C)

Audit and stabilization notes for realtime presence and delivery acknowledgements.

**Status:** PR20A + PR20C implemented on feature branches. Manual smoke **NOT RUN**.

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
  → ConversationDeliveryAckCoordinator (dedup, foreground gate)
  → PATCH /conversations/:id/delivered
Backend advances lastDeliveredAt if newer
  → conversation.delivered realtime + sync event (if advanced)
Sender UI applies deliveryStatus / conversation.delivered
```

Active chat: `markDelivered` then `markRead` independently — delivered does not wait for read success. Backend `markRead` also advances delivered (read implies delivered).

**Not implemented:** background/silent push delivery ack. **APNs acceptance ≠ delivered.**

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
| `deliveryMessageObserved` | inbound message seen in data layer |
| `deliveryAckScheduled` | ack path entered |
| existing `deliveredAckSent` / `Skipped` / `Failed` | REST ack result |

---

## Known limitations (product / platform)

1. **Background WebSocket:** default `messagesEnabled == false` disconnects WS in background → peer appears offline. Product policy undecided.
2. **No silent push delivery ack:** no `didReceiveRemoteNotification` handler; APNs success ≠ delivered.
3. **Foreground gate:** all delivery acks still require `UIApplication` active. Background ack is **PR20D2**.
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
2. Sync delta applied messages **without** scheduling ack (fixed in PR20A for foreground sync).
3. No background/silent push ack path.
4. Chat open is **not** the only trigger (list REST + inactive realtime also ack), but all require foreground.

**Deferred:** PR20D2 background acknowledgements; PR20D1 backend hardening.

---

## Reproduction matrix (manual smoke)

See PR20A report section 13. Status: **NOT RUN**.

---

## Privacy

Do not log: JWT, Authorization, WebSocket query tokens, message body/caption, signed URLs, full push payloads, absolute local paths.

Safe: truncated IDs, counts, durations, reasons, generation, scene/network state.
