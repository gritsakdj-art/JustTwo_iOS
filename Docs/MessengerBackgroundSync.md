# Messenger Background Sync (PR20D3B)

PR20D3B adds best-effort iOS reconciliation after hybrid or silent messenger pushes delivered by backend PR20D3A. Push payload is a **wake/sync hint only** — never delivery evidence.

## Push contract (PR20D3A)

Hybrid alert (user-facing allowed):

```json
{
  "aps": { "alert": { ... }, "content-available": 1 },
  "event": "message.created",
  "conversationID": "<uuid>",
  "messageID": "<uuid>"
}
```

Silent background (alert suppressed):

```json
{
  "aps": { "content-available": 1 },
  "event": "message.created",
  "conversationID": "<uuid>",
  "messageID": "<uuid>"
}
```

Both use the same iOS callback:

```text
AppDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)
```

## Core principle

```text
push callback
→ parse wake hint
→ bounded session recovery
→ MessengerSyncEngine.runGlobalSyncForBackground (authoritative PR20D2 pipeline)
→ atomic cursor + proven-safe boundary persistence
→ ConversationDeliveryAckCoordinator best-effort flush
→ UIBackgroundFetchResult exactly once
```

Never ACK `messageID` directly from push payload.

## State machine

```text
remote notification received
→ parseWakeIntent (event == message.created)
→ assign completion token to a batch cohort by phase:
      phase idle     → start a new current batch, run drain
      phase active   → join current batch, require a trailing cycle
      phase trailing → start / join the NEXT batch (not covered by current)
→ drain loop (one at a time, globally serialized):
      run active cycle for current batch
      if trailing required: run one trailing cycle
      finish current-batch waiters once (shared result)
      promote next batch if its own deadline has not expired,
        else expire its waiters (.failed) once
```

Maximum sync cycles per batch: **one active + one trailing**. A continuous push
stream never runs more than one sync at a time and never creates an unbounded
number of cycles.

### Cohorts (late-push correctness)

A push that arrives **after** the trailing cycle has started is *not* completed by
the current batch. It forms the next batch and runs its own bounded active(+trailing)
cycle afterwards. This prevents a late push from being falsely reported as covered
by a sync that started before it — the push payload is never treated as coverage.

### Absolute deadlines

Each callback carries its own absolute deadline (`receivedAt + operationDeadline`).
Dependency readiness, session preparation, active sync, trailing sync, and the ACK
flush all draw from that single deadline — no stage restarts a fresh 25s budget.
A batch uses the earliest waiter deadline; a promoted next batch keeps its own
(later) deadline rather than inheriting the previous, possibly expired, one.

### Durable ACK bootstrap on cold launch

Before the ACK flush, the current owner's durably persisted proven-safe boundaries
(PR20D2 `bootstrapPersistedBoundaries`) are loaded so a cold background launch with
no prior chat open can still ACK. Bootstrap is owner-scoped, generation-guarded
across awaits, safe to run twice, and never mixes accounts.

## UIBackgroundFetchResult mapping

| Result | When |
|--------|------|
| `.newData` | Authoritative sync applied new messenger state and/or advanced revision; durable boundaries saved. ACK network failure still `.newData`. |
| `.noData` | Non-messenger push, malformed hint, logged out, or sync succeeded with zero changes. |
| `.failed` | Offline, session unavailable, sync/apply/persistence failure, dependency deadline exceeded, stale session after sync. |

## Session readiness

Background path restores JWT from Keychain and may hydrate `StartupSessionSnapshot`. Does not present login UI.

| Session | Behavior |
|---------|----------|
| Authenticated + verified | Run sync |
| Logged out | `.noData` |
| Recovery failure | `.failed` |

Session generation + owner profile guards prevent cross-account application after logout/login.

## Authoritative pipeline reuse (PR20D2)

Background sync calls existing:

- `MessengerSyncEngine` / `MessengerDeltaSyncService`
- `commitAuthoritativeSyncPage`
- `ConversationDeliveryAckCoordinator.scheduleAuthoritativeBoundary`

Delivered ACK only after proven-safe boundary. Durable pending survives ACK network failure and replays on foreground/cold start.

## Read separation

Background path never calls `markRead` or read receipt endpoints.

## Image messages

Metadata persisted through authoritative sync. No full image byte download in background.

## Foreground sync join

`runGlobalSyncForBackground` joins an in-flight foreground/global sync via
`backgroundSyncWaiters` instead of issuing a second delta request. The background
completion receives the shared result. A background deadline expiring does not
cancel a useful in-flight foreground sync.

## Background execution lifetime

No `beginBackgroundTask` is used. The remote-notification callback itself provides
the background execution opportunity, the app calls `fetchCompletionHandler`
exactly once, and the operation is bounded by a single absolute deadline. No extra
`UIApplication` background task is created solely for ceremony.

## Best-effort limitations

```text
- iOS may delay or skip background execution
- force quit may prevent callback
- APNs may coalesce/throttle pushes
- foreground/cold-start fallback remains required
```

Manual staging + physical-device smoke: **NOT RUN** (requires backend PR20D3A on staging).

## Related docs

- [MessengerSyncEngine.md](MessengerSyncEngine.md)
- [MessengerPresenceAndDeliveryDiagnostics.md](MessengerPresenceAndDeliveryDiagnostics.md)
- [MessengerOfflineUX.md](MessengerOfflineUX.md)
- [MessengerLocalStorage.md](MessengerLocalStorage.md)
