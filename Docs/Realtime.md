# Realtime Client Foundation

PR5 adds the iOS realtime client foundation for the canonical backend endpoint:

```text
wss://api.jtwo.online/ws/realtime
```

The app uses JWT `Authorization: Bearer <token>` WebSocket auth. Query-token auth is backend fallback only and is not used by the iOS client.

## Scope

Implemented in PR5:

* authenticated `URLSessionWebSocketTask` connection;
* `RealtimeConnectionState`;
* client messages: `ping`, `subscribe.conversation`, `unsubscribe.conversation`, `typing.started`, `typing.stopped` (PR7);
* server event decoding for PR2/PR3/PR4/PR7 realtime events;
* resilient unknown-event and payload decoding;
* `AsyncStream` event routing through `RealtimeEventRouter`;
* reconnect with capped exponential backoff;
* foreground reconnect and background disconnect;
* clean disconnect on logout, account deletion, and session invalidation.

Not implemented in PR5:

* chat UI/store mutation from realtime events;
* missed-message reconciliation after reconnect;
* presence;
* APNs/background push;
* background WebSocket persistence.

PR6 added messenger UI integration. PR7 added typing indicators in active chat. PR8B added ephemeral presence indicators in the conversation list and active private chat header.

## Lifecycle

Realtime connects only when the app has a fully authenticated, email-verified session and a JWT is available in `APIAuth`.

Connection starts after:

* verified login;
* verified session restore;
* app returning to foreground with a valid verified session.

Connection stops on:

* logout;
* account deletion;
* auth/session invalidation;
* app entering background.

Realtime failure does not block login and does not log the user out by itself. REST remains the source of truth.

PR15B: realtime and delta handlers update both the in-memory conversation list and the local conversation cache (`MessengerConversationCacheService`).

PR15C: realtime and delta message handlers also persist per-conversation message history to local DB (`MessengerMessageCacheService`).

**PR15C limitation:** realtime `reaction.added` / `reaction.removed` events without a full `MessageDTO` snapshot update in-memory reaction UI only; local reaction aggregates are repaired on the next delta event with message snapshot or REST refresh.

PR17: realtime remains a **foreground accelerator** only. The persistent global sync cursor is owned by `MessengerSyncEngine` delta loop — realtime does not advance `lastAppliedRevision`. Delta sync repairs missed events after reconnect/relaunch.

**PR15C limitation:** realtime `reaction.added` / `reaction.removed` events without a full `MessageDTO` snapshot update in-memory reaction UI only; local reaction aggregates are repaired on the next delta event with message snapshot or REST refresh.

## Event handling

`RealtimeEventDTO` decodes:

* `connection.ready`;
* `pong`;
* `error`;
* `subscription.ready`;
* `subscription.removed`;
* `message.created`;
* `message.edited`;
* `message.deleted`;
* `reaction.added`;
* `reaction.removed`;
* `conversation.read`;
* `conversation.updated`;
* `typing.started` / `typing.stopped` (PR7);
* `presence.changed` (PR8B);
* unknown future event types.

`message.deleted` is intentionally decoded without requiring a message body.

`reaction.added` accepts the current backend `count` shape as either `Bool` or future `Int` through `RealtimeReactionCount`.

## Presence (PR8B)

`presence.changed` updates `PresenceStore` through `MessengerRealtimeCoordinator`.

* online/offline is ephemeral and not persisted locally;
* unknown participant presence is treated as offline;
* own presence events are ignored;
* presence clears on logout, background disconnect, and reconnect reconcile;
* conversation list rows and private chat header show a small online indicator when the other participant is online;
* REST remains the source of truth for messenger data.

## Offline startup (PR15D)

When splash routes to `MainTabView` using a cached session snapshot:

* realtime connect is **deferred** until `StartupSessionValidationService` succeeds;
* `MessengerSyncEngine` hydrates persisted cursor, runs background global delta sync (non-blocking);
* startup does not block `MainTabView` on sync completion;
* transient network loss during an active session keeps existing realtime behavior unchanged.

## Image attachments offline (PR15E)

Realtime/delta may deliver image messages without a persistable signed URL in local DB. After an image was once loaded online:

* disk cache keyed by `attachmentID` allows offline bubble/viewer rendering;
* realtime does not write image bytes to SwiftData;
* delete events still clear renderable attachments and remove disk cache files.

PR15F offline fail-fast and startup local-DB-first do not change disk cache behavior; cached images still render when network REST is skipped.

## Manual smoke

Use staging only:

```text
https://api.jtwo.online
wss://api.jtwo.online/ws/realtime
```

Suggested Xcode-log smoke:

1. Launch the app.
2. Login as a verified user.
3. Confirm `Realtime connect start`.
4. Confirm `Realtime connection ready`.
5. Background the app.
6. Confirm `Realtime disconnected`.
7. Foreground the app.
8. Confirm reconnect and `connection.ready`.
9. Logout.
10. Confirm disconnect and no reconnect.

If PR6 wires chat screen subscriptions, also confirm:

1. Open a known conversation.
2. Send `subscribe.conversation`.
3. Decode `subscription.ready`.
4. Trigger REST message/reaction/read/delete operations.
5. Decode PR4 events without mutating UI state in PR5.
