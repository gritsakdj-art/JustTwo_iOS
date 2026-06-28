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
* client messages: `ping`, `subscribe.conversation`, `unsubscribe.conversation`;
* server event decoding for PR2/PR3/PR4 realtime events;
* resilient unknown-event and payload decoding;
* `AsyncStream` event routing through `RealtimeEventRouter`;
* reconnect with capped exponential backoff;
* foreground reconnect and background disconnect;
* clean disconnect on logout, account deletion, and session invalidation.

Not implemented in PR5:

* chat UI/store mutation from realtime events;
* missed-message reconciliation after reconnect;
* typing indicators;
* presence;
* APNs/background push;
* background WebSocket persistence.

Those belong to later realtime PRs.

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
* unknown future event types.

`message.deleted` is intentionally decoded without requiring a message body.

`reaction.added` accepts the current backend `count` shape as either `Bool` or future `Int` through `RealtimeReactionCount`.

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
