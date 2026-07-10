# Messenger Presence And Delivery Diagnostics (PR20A)

Audit and stabilization notes for realtime presence and delivery acknowledgements.

**Status:** Implemented on diagnostic/stabilization branches. Manual smoke **NOT RUN**.

Related roadmap:

| PR | Scope |
|----|--------|
| **PR20A** (this doc) | Diagnostics, local defect fixes, tests |
| PR20B | Backend persisted `lastSeenAt` / presence summary |
| PR20C | iOS last-seen UI and presence reconciliation |
| PR20D1 | Backend delivery receipt hardening |
| PR20D2 | iOS background/foreground delivery acknowledgements |

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

### iOS presence

```text
RealtimeClient URLSessionWebSocketTask
  → connection.ready → flush subscriptions
  → presence.changed → PresenceStore source=realtime (authoritative, no TTL)
  → typing.started (active chat) → PresenceStore source=typingHint (TTL 15s)
  → typing.stopped → clearTypingHint only
  → reconnect → markAllPreservedAcrossReconnect (source=preserved, TTL 90s)
Conversation list / PrivateChatView read PresenceStore.isOnline
REST / SwiftData / sync do NOT carry presence
Explicit disconnect / logout clears PresenceStore
```

#### Backend-authoritative presence vs typing hint

| Kind | Source | Persisted? | TTL | Cleared by |
|------|--------|------------|-----|------------|
| Backend-authoritative | `presence.changed` → `.realtime` | No (memory only) | None | offline event, logout, explicit disconnect |
| Typing activity hint | `typing.started` → `.typingHint` | No | 15s | `typing.stopped`, TTL, realtime offline, logout |
| Provisional reconnect | `.preserved` | No | 90s | realtime event, TTL, logout |

Typing hint is **not** authoritative presence and is never written to SwiftData/cache.

#### Reconnect freshness (bounded, not complete)

Preserving presence avoids false offline while typing after short reconnects. Entries are remapped to `.preserved` with a 90s TTL. This is **provisional**, not a new backend observation. Missed offline during long disconnect / backend restart can leave stale online until TTL or next realtime event. Full fix: **PR20B/PR20C**.

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
