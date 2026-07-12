# Messenger Realtime Receipts (PR20D4B)

## Scope

PR20D4B makes `conversation.delivered` and `conversation.read` global messenger state events on iOS.

The client now:

- receives receipt events on the shared WebSocket without requiring `subscribe.conversation`
- routes them through one canonical coordinator
- applies monotonic participant receipt boundaries to SwiftData
- updates cached outgoing message `deliveryStatus`
- updates the Chats list preview receipt indicator for the current user's last outgoing message
- refreshes `PrivateChatView` through the shared cache notification bridge

PR20D4B does **not** send delivery/read ACKs. Outbound ACK remains owned by `ConversationDeliveryAckCoordinator`.

## Backend contract (PR20D4A)

Backend publishes `conversation.delivered` and `conversation.read` to all live WebSocket connections for active conversation participants.

Payload keys used by iOS:

```text
type
conversationID
payload.profileID
payload.messageID
payload.lastDeliveredAt
payload.lastReadAt
```

Receipt subscription is not required. One logical event is delivered once per socket.

## iOS route

```text
RealtimeClient
→ RealtimeEventRouter
→ MessengerRealtimeCoordinator
→ MessengerRealtimeReceiptCoordinator
→ MessengerLocalStore.applyRealtimeReceipt(...)
→ MessageCacheStore / ConversationListViewModel
→ SwiftUI
```

Delta sync receipt events use the same coordinator so realtime and sync do not maintain separate apply systems.

## Canonical apply rules

For each participant/conversation boundary:

```text
delivered boundary is monotonic
read boundary is monotonic
read implies delivered
ordering uses (createdAt, messageID) with PostgreSQL UUID byte tie-break
```

Counterparty receipt boundaries update only:

```text
outgoing messages owned by the current account
in the same conversation
at or below the boundary
with a strictly higher deliveryStatus
```

Self-echo (`participantProfileID == ownerProfileID`):

```text
updates participant receipt state for multi-device reconciliation
does not promote own outgoing message ticks
does not schedule outbound ACK
```

## Missing target message

If the boundary `messageID` is not present locally:

```text
no message statuses are upgraded
requiresSyncRepair = true
one coalesced global delta sync is scheduled
pending hints are retried after sync
```

The client does not compare boundaries by UUID alone and does not mass-promote unknown prefixes.

## UI behavior

- `PrivateChatView` observes `MessengerConversationNotification.postMessagesDidChange`
- `ChatsView` shows outgoing receipt ticks via `ChatConversationPreview.lastOutgoingDeliveryStatus`
- receipt events do not change conversation sort order
- unread count is unchanged by counterparty delivered/read events

## Fallback

Realtime receipt apply is best-effort. Missed events are recovered by delta sync. Duplicate events after reconnect are no-op.

## Lifecycle and reset

`MessengerRealtimeReceiptCoordinator.shared` is a process-wide singleton. Production logout calls `reset()` from `SessionStore.clearSession()`.

`reset()`:

```text
increments sessionGeneration
cancels in-flight apply drain and repair tasks
clears ownerProfileID, pending apply queue, and repair hints
resets isApplyInFlight / isRepairInFlight / hasPendingRepair
```

In-flight `applyReceipt` work captures `sessionGeneration` at entry and re-checks after every `await`. Stale work exits without mutating the local store or observable caches.

Repair coalescing state is cleared on reset; a cancelled repair task does not schedule trailing sync for the next account.

## Test isolation

Receipt-related test suites use `@Suite(.serialized)` where they touch shared singletons (`MessengerRealtimeReceiptCoordinator`, `MessengerLocalStore.shared`, `MessageCacheStore.shared`).

`MessengerDeltaSyncBehaviorTests` is serialized because async receipt apply replaced the previous synchronous delta cache update.

## Manual smoke

Status: `NOT RUN`

Requires backend PR20D4A deployed to staging and a physical iPhone smoke pass.
