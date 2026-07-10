# JustTwo iOS Optimization Batches

This document translates the Analysis audit into executable Cursor prompts. Each batch
must be implemented on a separate branch, reviewed independently, and reported back in
this file after completion.

General rules for every batch:

- Work in the iOS repository: `/Users/dina/projects/JustTwo/JustTwo`.
- Create a new branch before editing.
- Keep changes scoped to the current batch.
- Do not mix unrelated UI polish with infrastructure fixes.
- Do not rewrite navigation, persistence, realtime, or network architecture unless the
  batch explicitly asks for it.
- Preserve existing diagnostics where possible, and add small targeted diagnostics only
  when they make the fix verifiable.
- Run the narrowest useful checks first, then a full iOS build.
- Update the "Batch Completion Report" section at the end of this file before commit.

Recommended verification command:

```bash
xcodebuild -project JustTwo.xcodeproj -scheme JustTwo -destination 'platform=iOS Simulator,name=iPhone 16' build
```

If the simulator name is unavailable locally, pick an installed iPhone simulator and
record the exact command in the completion report.

## Batch A - Realtime Consistency

Branch:

```bash
git checkout main
git pull --ff-only
git checkout -b batch-a-realtime-consistency
```

Cursor prompt:

```text
You are working in the iOS repository JustTwo.

Goal:
Fix realtime message delivery consistency without reintroducing heavy duplicate
PrivateChatView observers or broad MainActor work.

Context:
The app previously had symptoms where a message was visible in the conversation list
but did not appear in PrivateChatView until another local action happened. Recent fixes
removed duplicate cache observers from PrivateChatView for performance. Keep that
direction: ChatViewModel and MessageCacheStore should remain the source of truth.

Tasks:
1. Inspect:
   - Shared/Views/Chats/MessengerRealtimeCoordinator.swift
   - Shared/Views/Chats/ViewModels/ChatViewModel.swift
   - Shared/Views/Chats/MessageCacheStore.swift
   - Shared/Views/Chats/MessengerConversationNotification.swift

2. Fix active-chat fallback:
   - In MessengerRealtimeCoordinator, when activeConversationID matches the incoming
     conversation but activeChatViewModel is nil, do not drop the event.
   - Apply the event through MessageCacheStore fallback for:
     - message.created
     - message.edited
     - message.deleted
     - reaction added/removed
     - delivered/read receipt updates, if the current code has the same weak-view-model
       risk there.
   - Keep behavior unchanged when activeChatViewModel exists and applies the event.

3. Fix cache mutation return semantics:
   - Review MessageCacheStore methods that mutate cache and return Bool.
   - Make the returned value mean "cache/messages changed in a way callers should care
     about", not only "inserted new message".
   - If an existing message is updated, edited, deleted, reaction-mutated, or receipt
     state changes, return true when the stored value actually changed.
   - Do not return true for exact no-op updates.

4. Keep performance guardrails:
   - Do not re-add broad .onReceive observers to PrivateChatView.
   - Do not force refresh the whole conversation on every realtime event.
   - Do not change scroll or keyboard logic.
   - Avoid large refactors.

5. Diagnostics:
   - Rename or clarify diagnostics if they currently log "inserted" when the value now
     means "applied" or "mutated".
   - Add one small diagnostic for the nil activeChatViewModel fallback path.

6. Verification:
   - Build the project with xcodebuild.
   - Manual smoke checklist:
     - Open a chat, background the app, receive a message, foreground the app.
     - Confirm the message appears in PrivateChatView without sending your own message.
     - Confirm conversation list preview and chat contents agree.
     - Confirm message edit/delete/reaction events still update the active chat.

7. Update Docs/Batches.md:
   - Fill in the Batch A completion report:
     - branch name
     - files changed
     - summary
     - tests/build result
     - manual smoke result
     - known residual risks

Do not implement any Batch B-E changes in this branch.
```

## Batch B - Auth, Session, Push Routing

Branch:

```bash
git checkout main
git pull --ff-only
git checkout -b batch-b-auth-session-push-routing
```

Cursor prompt:

```text
You are working in the iOS repository JustTwo.

Goal:
Make authenticated network requests, session-scoped async tasks, and push/deeplink chat
routing deterministic and safe across logout/login, app activation, and repeated push
taps.

Tasks:
1. Inspect:
   - Core/Network/HTTPClient.swift
   - Core/Network/APIAuth.swift
   - Core/Session/SessionStore.swift
   - Core/Push/PushRegistrationService.swift
   - Core/Push/PushNotificationRoutingCoordinator.swift
   - Router/AppRouter.swift
   - Shared/Views/Chats/ChatsView.swift

2. Authenticated request guard:
   - In HTTPClient request creation/execution path, fail fast when request.requiresAuth
     is true and there is no non-empty access token.
   - Return/throw the existing unauthorized NetworkError style used elsewhere.
   - Do not send authenticated endpoints to the backend without Authorization.
   - Do not log tokens.

3. Session-scoped async tasks:
   - In SessionStore, capture a stable user/session identifier before launching async
     tasks that sync push, connect realtime, or run background messenger sync.
   - Re-check that the same user/session is still active before applying results or
     starting side effects that belong to a user.
   - Logout/unregister flows must not be blocked.
   - Keep changes small; do not redesign SessionStore.

4. Push registration safety:
   - Verify PushRegistrationService does not sync a token for a stale user after logout
     or fast account switch.
   - If there is an in-flight sync for one user and the user changes, ensure a later sync
     for the new user is not permanently blocked.
   - Keep backend API unchanged.

5. Push/deeplink routing:
   - In PushNotificationRoutingCoordinator, do not clear pendingRoute before the target
     conversation is found and openChat is called.
   - Add an isApplyingRoute or equivalent guard so repeated applyPendingRouteIfPossible
     calls do not start competing tasks for the same route.
   - If refresh does not find the conversation, keep the pending route for a later retry,
     but avoid infinite tight retry loops.
   - Ensure selectedMainTab becomes .chats when routing to a conversation.

6. Chat navigation identity:
   - In ChatsView.ChatRoute, include targetMessageID in the route identity or otherwise
     ensure a push to the same conversation with a different messageID can update the
     destination.
   - Do not break normal row tap navigation.
   - Do not change PrivateChatView scroll logic in this batch.

7. Verification:
   - Build with xcodebuild.
   - Manual smoke checklist:
     - Tap push when app is cold.
     - Tap push when app is already on Discover.
     - Tap push for same conversation with a different messageID.
     - Logout/login and verify no stale push registration or realtime task affects the
       new user.
     - Confirm no authenticated request is sent without Authorization.

8. Update Docs/Batches.md Batch B completion report.

Do not implement Batch A, C, D, or E changes in this branch.
```

## Batch C - Startup And Background Warmup

Branch:

```bash
git checkout main
git pull --ff-only
git checkout -b batch-c-startup-background-warmup
```

Cursor prompt:

```text
You are working in the iOS repository JustTwo.

Goal:
Reduce startup/background warmup races and MainActor pressure without changing the
visible startup flow.

Tasks:
1. Inspect:
   - Core/Startup/AppStartupCoordinator.swift
   - Core/Startup/StartupSingleFlight.swift
   - Core/Session/SessionStore.swift
   - Shared/Views/Chats/MessengerSyncEngine.swift
   - Shared/Views/Chats/MessageCacheStore.swift
   - any startup warmup/preload helpers referenced from AppStartupCoordinator.

2. StartupSingleFlight cancellation correctness:
   - Ensure a canceled operation does not mark its key as loaded.
   - Ensure a replaced task cannot clear or mark the state of a newer task.
   - Keep the public API stable unless a tiny signature change is clearly necessary.

3. Background warmup single-flight/generation:
   - Add a lightweight guard so repeated calls to background network warmup do not spawn
     overlapping duplicate work for the same user/session.
   - Capture a stable user/session identifier and re-check it before applying results.

4. Child task ownership:
   - Review unstructured Task usage inside background warmup.
   - Prefer structured async where practical.
   - If an unstructured Task remains necessary, make sure it captures stable session/user
     context and exits early if stale.

5. Preload throttling:
   - Limit aggressive conversation/message/media preload concurrency.
   - Keep startup responsive; do not load too many conversations at once on MainActor.
   - Avoid changing user-visible loading states unless necessary.

6. Diagnostics:
   - Add small diagnostics for skipped duplicate warmup and stale warmup cancellation.
   - Do not spam logs in normal successful startup.

7. Verification:
   - Build with xcodebuild.
   - Manual smoke checklist:
     - Fresh app launch with valid session.
     - App foreground/background/foreground several times quickly.
     - Logout during/soon after startup.
     - Login as same user again.
     - Confirm no duplicate warmup storm in logs.

8. Update Docs/Batches.md Batch C completion report.

Do not implement persistence or profile image refactors in this branch.
```

## Batch D - Persistence And Local Cache

Branch:

```bash
git checkout main
git pull --ff-only
git checkout -b batch-d-persistence-local-cache
```

Cursor prompt:

```text
You are working in the iOS repository JustTwo.

Goal:
Fix local message pagination correctness and reduce obvious SwiftData N+1 overhead while
avoiding a risky persistence architecture rewrite.

Tasks:
1. Inspect:
   - Shared/Views/Chats/SwiftDataMessengerLocalStore.swift
   - Shared/Views/Chats/MessageCacheStore.swift
   - Shared/Views/Chats/Models/ChatUIModels.swift
   - any SwiftData entities for messages, attachments, and reactions.

2. Fix before-pagination correctness:
   - In fetchLocalMessages(before:limit:), ensure the before cutoff is part of the fetch
     predicate before fetchLimit is applied.
   - The returned page should contain messages older than before, not the latest limited
     messages filtered afterward.
   - Keep sort order consistent with current UI/cache expectations.

3. Reduce N+1 attachment/reaction fetches:
   - If current code fetches attachments/reactions per message, replace with batched
     fetches for the page's message IDs.
   - Preserve ordering of attachments/reactions.
   - Keep mapping behavior identical.

4. Avoid broad refactor:
   - Do not move the whole store to ModelActor in this batch.
   - Do not change backend DTOs or cache API unless absolutely necessary.
   - Do not change chat scroll or realtime logic.

5. Optional small file I/O cleanup:
   - If pending media cleanup/deletion does synchronous file work on MainActor and can be
     safely moved off-main with a tiny change, do it.
   - If it would broaden the batch too much, leave it as a noted follow-up.

6. Verification:
   - Build with xcodebuild.
   - Manual smoke checklist:
     - Open chat from warm cache.
     - Paginate older messages.
     - Confirm image attachments still render.
     - Confirm reactions still render.
     - Confirm offline cached messages still open.

7. Update Docs/Batches.md Batch D completion report.

Do not implement startup, push routing, or profile-photo changes in this branch.
```

## Batch E - Profile Photo And Misc MainActor I/O

Branch:

```bash
git checkout main
git pull --ff-only
git checkout -b batch-e-profile-photo-mainactor-io
```

Cursor prompt:

```text
You are working in the iOS repository JustTwo.

Goal:
Move obvious profile-photo disk read/decode/encode work off the main actor and reduce
UI jank risk in profile/avatar flows.

Tasks:
1. Inspect:
   - Shared/Views/Profile/ProfilePhotoImageCache.swift
   - Shared/Views/Profile/ProfilePhotoStore.swift
   - Shared/Views/Profile/AvatarCropEditorView.swift
   - any profile photo upload/download/cache pipeline helpers.

2. Off-main disk reads and image decode:
   - Replace synchronous main-thread Data(contentsOf:) and UIImage(data:) usage in profile
     photo cache paths with async/off-main work.
   - Keep API ergonomics reasonable for SwiftUI callers.
   - Preserve existing cache behavior and file locations.

3. Off-main encode:
   - Move jpegData or other expensive encoding work off MainActor where possible.
   - Keep image quality and upload behavior unchanged.

4. Avatar crop flow:
   - Ensure crop/export work does not block UI for large images.
   - Keep the UI and gestures unchanged.

5. Safety:
   - Do not change backend API.
   - Do not change chat media cache in this batch unless the same helper is shared and
     the change is trivial.
   - Do not introduce new third-party dependencies.

6. Verification:
   - Build with xcodebuild.
   - Manual smoke checklist:
     - Open profile settings.
     - Pick/crop/upload profile photo.
     - Reopen app and confirm cached avatar loads.
     - Scroll screens with avatars and check for reduced jank.

7. Update Docs/Batches.md Batch E completion report.

Do not implement chat realtime, startup, or persistence changes in this branch.
```

## Batch Completion Report

Cursor should append/update the relevant subsection after each batch is implemented.

### Batch A - Realtime Consistency

Status: Implemented (pending manual smoke)

Branch: `batch-a-realtime-consistency`

Files changed:
- `JustTwo/Shared/Views/Chats/MessengerRealtimeCoordinator.swift`
- `JustTwo/Shared/Views/Chats/MessageCacheStore.swift`
- `JustTwo/Shared/Views/Chats/ViewModels/ChatViewModel.swift`
- `JustTwo/Shared/Diagnostics/MessengerDiagnostics.swift`
- `JustTwoTests/RealtimeTests.swift`
- `JustTwoTests/MessageCacheStoreTests.swift`

Summary:
- Added `applyToActiveConversation` helper: when `activeConversationID` matches but `activeChatViewModel` is nil, events apply through `MessageCacheStore` instead of being dropped.
- Fixed cache Bool semantics: `upsertMessage` returns `true` on edits; delete/reaction methods return `false` on no-op.
- New diagnostic `realtimeActiveChatViewModelNilFallback`; message event reasons renamed to `activeChatApplied` / path metadata.
- Follow-up fix: duplicate/no-op reaction events no longer trigger active-chat refresh when the message is already present.
- Follow-up fix: realtime `reaction.added` now preserves `reactedByMe` from payload in active chat and cache fallback paths.
- No broad `PrivateChatView` observers re-added.

Build/tests:
- `xcodebuild -project JustTwo.xcodeproj -scheme JustTwo -destination 'platform=iOS Simulator,id=D1806BCC-C599-4B19-A8F4-96B9A3BCE81E' build` — SUCCEEDED
- `xcodebuild test ... -only-testing:JustTwoTests/RealtimeTests -only-testing:JustTwoTests/MessageCacheStoreTests` — 38 tests SUCCEEDED

Manual smoke:
- Not run (see Batch A checklist in prompt above)

Residual risks / follow-up:
- Nil-VM fallback relies on `MessageCacheStore` + `MessengerConversationNotification`; open `ChatViewModel` must still be subscribed for UI refresh.
- `refreshActiveChatFromRealtime()` remains no-op without a live view model (by design).
- Batch B–E unchanged.

### Batch B - Auth, Session, Push Routing

Status: Implemented (pending manual smoke)

Branch: `batch-b-auth-session-push-routing`

Files changed:
- `JustTwo/Core/Network/HTTPClient.swift`
- `JustTwo/Core/Session/SessionStore.swift`
- `JustTwo/Core/Push/PushRegistrationService.swift`
- `JustTwo/Core/Push/PushNotificationRoutingCoordinator.swift`
- `JustTwo/Router/AppRouter.swift`
- `JustTwo/Shared/Views/Chats/ChatsView.swift`
- `JustTwoTests/HTTPClientAuthGuardTests.swift` (new)
- `JustTwoTests/PushNotificationRoutingCoordinatorTests.swift` (new)
- `JustTwoTests/PushRegistrationTests.swift`

Summary:
- `HTTPClient` fails fast with `NetworkError.unauthorized` when `requiresAuth` and token is missing/empty.
- `SessionStore` async tasks capture `sessionUserID` and re-check before side effects (realtime, push sync, foreground sync).
- `PushRegistrationService.resetSessionState()` on logout; session re-check before network send; `pendingSyncUserID` queue when in-flight sync is for another user.
- Push routing keeps `pendingRoute` until `openChat` succeeds; `applyingRouteKey` guard; debounced retry when conversation missing.
- `AppRouter.pendingChatNavigationID` + `ChatRoute.id` includes message target for same-conversation re-navigation.

Build/tests:
- `xcodebuild -project JustTwo.xcodeproj -scheme JustTwo -destination 'platform=iOS Simulator,id=D1806BCC-C599-4B19-A8F4-96B9A3BCE81E' build` — SUCCEEDED
- `xcodebuild test ... -only-testing:JustTwoTests/HTTPClientAuthGuardTests -only-testing:JustTwoTests/PushNotificationRoutingCoordinatorTests -only-testing:JustTwoTests/PushRegistrationTests` — 9 tests SUCCEEDED

Manual smoke:
- Not run (see Batch B checklist in prompt above)

Residual risks / follow-up:
- Push route retry still depends on later `applyPendingRouteIfPossible` triggers (sign-in, foreground, main reset).
- Coordinator testing hooks (`testingBypassApplyGuards`, etc.) are internal; production defaults are safe.
- Batch C–E unchanged.

### Batch C - Startup And Background Warmup

Status: Implemented (pending manual smoke)

Branch: `batch-c-startup-background-warmup`

Files changed:
- `JustTwo/Bootstrap/Startup/StartupSingleFlight.swift`
- `JustTwo/Bootstrap/Startup/AppStartupCoordinator.swift`
- `JustTwo/Bootstrap/Startup/StartupSessionValidationService.swift`
- `JustTwo/Bootstrap/Startup/StartupLoadingLimits.swift`
- `JustTwo/Shared/Views/Chats/MessageCacheStore.swift`
- `JustTwo/Shared/Diagnostics/MessengerDiagnostics.swift`
- `JustTwoTests/StartupSingleFlightTests.swift`
- `JustTwoTests/AppStartupCoordinatorTests.swift`

Summary:
- `StartupSingleFlight`: waiter loop coalesces replaced tasks; canceled ops no longer set `loadedKey` (operation ID guard).
- Follow-up fix: operations can report unsuccessful completion; aborted/stale background warmup no longer marks its user key as loaded.
- Follow-up fix: waiters that were suspended on an old task exit after `reset()` instead of starting stale work.
- Background warmup uses `backgroundWarmupFlight` per user; duplicate calls emit `startupBackgroundNetworkWarmupSkippedDuplicate`.
- Follow-up fix: forced background warmup now propagates `force` into profile photo, conversation network refresh, and message preload loaders.
- Follow-up fix: background warmup wrapper uses operation ID ownership so stale/canceled wrappers cannot clear a newer task reference.
- `performBackgroundNetworkWarmup` re-checks `expectedUserID` and `Task.isCancelled` at key stages; stale abort diagnostic added.
- Child sync/outbox/cleanup tasks guard session before running.
- `StartupSessionValidationService` routes through `scheduleBackgroundNetworkWarmup` instead of direct duplicate call.
- Conversation list network refresh now coalesces in-flight refreshes so main tab loading and background warmup do not issue duplicate `/conversations` requests; coalesced callers emit `messengerConversationCacheNetworkRefreshCoalesced`.
- Message preload bounded to 3 concurrent workers; removed fire-and-forget partial-cache network preload task.

Build/tests:
- Initial Cursor run: `xcodebuild -project JustTwo.xcodeproj -scheme JustTwo -destination 'platform=iOS Simulator,id=D1806BCC-C599-4B19-A8F4-96B9A3BCE81E' build` — SUCCEEDED
- Initial Cursor run: `xcodebuild test ... -only-testing:JustTwoTests/StartupSingleFlightTests -only-testing:JustTwoTests/AppStartupCoordinatorTests` — 9 tests SUCCEEDED
- Follow-up check: `git diff --check` — PASSED
- Follow-up xcodebuild retry in Codex sandbox did not complete because CoreSimulator/runtime services were unavailable (`No available simulator runtimes` / `iOS 26.5 Platform Not Installed`); no Swift compiler errors were observed before asset/storyboard compilation failed.

Manual smoke:
- Not run (see Batch C checklist in prompt above)

Residual risks / follow-up:
- Long background warmup awaits are still cooperative only at explicit checkpoint guards; this is acceptable for Batch C but should stay visible during smoke.
- Batch D–E unchanged.

### Batch D - Persistence And Local Cache

Status: Not started

Branch:

Files changed:

Summary:

Build/tests:

Manual smoke:

Residual risks / follow-up:

### Batch E - Profile Photo And Misc MainActor I/O

Status: Not started

Branch:

Files changed:

Summary:

Build/tests:

Manual smoke:

Residual risks / follow-up:
