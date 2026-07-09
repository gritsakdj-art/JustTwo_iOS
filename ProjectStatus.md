# Project Status

## 2026-06-15

- Refactored app startup to open `DiscoverView` instead of the old home/content flow.
- Added `DiscoverView` preview support with mock profiles.
- Added a mock profile image asset at `Assets.xcassets/emma_profile.imageset`.
- Moved the custom tab bar into `Shared/Components/AppTabBar.swift`.
- Added placeholder screens for Matches, Chats, Plans, and Profile.
- Added shared placeholder UI in `Shared/Views/PlaceholderTabScreen.swift`.
- Added centralized color, gradient, spacing, and typography tokens in `Color+App.swift`.
- Added dynamic light/dark color tokens for the Discover UI.
- Removed the old `ContentView.swift`.
- Added `ReadMe.md` and `ProjectStatus.md` to document the project and ongoing changes.
- Prepared the app for localization with `Localizable.xcstrings`.
- Added English, Russian, Spanish, French, German, Italian, and Arabic localizations for the current UI.
- Added Arabic RTL previews for the Discover screen and custom tab bar.
- Replaced current hardcoded UI strings with localized keys and resources.
- Added localized accessibility labels for icon-only Discover actions.
- Registered supported localization regions in the Xcode project.
- Replaced the Profile placeholder with a two-section `ProfileView` containing avatar/user info, settings menu rows, and a bottom logout action.
- Added reusable `PrimaryButton` in `Shared/Components/UI`.
- Added dynamic brand color tokens in `Color+App.swift` for primary actions.
- Added dynamic brand gradients for `PrimaryButton` default and pressed states.
- Added localized profile menu and logout strings.
- Reorganized tab screens into per-tab folders under `Shared/Views` and removed the old `Features` folder.
- Added `GeneralSettingsView` under `Shared/Views/Profile`.
- Connected the Profile "General settings" menu item to `GeneralSettingsView` with `NavigationStack`.
- Added persisted app theme selection with System, Light, and Dark options.
- Applied the selected theme globally through `preferredColorScheme`.

## 2026-06-18

- Added staging API configuration for `https://api.jtwo.online`.
- Added the shared networking foundation with request building, URLSession execution, API decoding, and structured network errors.
- Added auth API requests and response models for register, login, and current user/profile loading.
- Added session state management for app startup, authenticated routing, unauthenticated routing, and profile loading.
- Added token persistence through Keychain-backed `TokenStorage`.
- Removed JWT token persistence from `UserDefaults`.
- Added session recovery handling when a saved token cannot load the current user.
- Added localized session recovery UI with retry support.
- Added robust ISO-8601 date decoding with and without fractional seconds.
- Added typed API error response decoding and localized user-facing server error messages.
- Added localized handling for auth, profile, validation, and session errors.
- Added reactive email validation on the auth screen.
- Added reactive registration password validation on the auth screen.
- Updated `BaseTextField` to display localized inline validation errors and error styling.
- Updated auth submit validation so invalid email formats cannot be submitted.
- Added localized strings for the new validation, server error, retry, and session recovery messages.
- Added `.gitignore` entries for Xcode user data, DerivedData, SwiftPM artifacts, and macOS metadata.
- Verified the iOS app builds successfully with `xcodebuild`.
- Confirmed there is currently no separate test target in the Xcode project.
- Added email verification DTO support for `emailVerified`, `emailVerifiedAt`, and future register responses without JWT.
- Added client API requests for resend verification and verify-email.
- Added soft email verification state to the session without blocking the current backend compatibility mode.
- Added `CheckEmailView` with resend cooldown, refresh-current-user check, loading, success, and error states.
- Added `EmailVerificationResultView` for magic link success, invalid/expired link, network error, and generic error states.
- Added email verification deep link parsing for `https://api.jtwo.online/auth/verify-email?token=...`.
- Added redacted network URL logging so verification tokens are not printed in debug logs.
- Added localized strings for email verification flow and new backend error codes.
- Added `Docs/EmailVerification.md` with backend endpoint notes, universal links checklist, AASA examples, and current staging compatibility mode.
- Added iOS API support for backend PR4 auth account lifecycle endpoints: forgot password, reset password, and delete account.
- Added forgot password UX on the auth screen that appears only after invalid login credentials.
- Added account deletion flow in profile settings with destructive confirmation, current password confirmation, session clearing, and localized errors.
- Added password reset Universal Link handling for `https://api.jtwo.online/auth/reset-password?token=...`.
- Added `ResetPasswordView` with new password confirmation, client-side password validation, backend reset submission, and return-to-login flow.

### Invite links, QR flow, and chat polish

- Added direct invite creation UI in `InviteLinkView` from the Chats `+` action.
- Added server-backed invite sharing with copy link, share link, share QR image, and refresh actions.
- Added client-side QR generation in `QRCodeGenerator` from backend `inviteURL` only.
- Added `InvitePreviewView` for Universal Link and pasted invite URLs with accept, decline, and block actions.
- Added invite deep link parsing for `https://api.jtwo.online/invite/{token}` in `DeepLinkParser`.
- Added `AppDeepLinkHandler` and router state for pending invite tokens and post-accept chat navigation.
- Added `InviteService` API wiring for create, preview, accept, and delete invite endpoints.
- Added `ProfileBlockService` and `BlockProfileRequest` for invite preview blocking.
- Added localized invite strings for English, Russian, German, Spanish, French, Italian, and Arabic.
- Added `JustTwoTests` target with parser, QR, and invite view model coverage.
- Refined `PrivateChatView` with partner avatar in the navigation bar and `ChatPatternBackground` wallpaper.
- Refined `ChatBubbleView` minimum width so edited-message timestamps stay inside the bubble.
- Added `Docs/InviteLinks.md` with endpoint contracts, deep link rules, file map, and manual test notes.
- Verified iOS build with `xcodebuild`.

### Startup loading and message cache

- Split splash warmup into `AppStartupCoordinator` and focused startup loaders.
- Added `ProfileStartupLoader`, `ProfilePhotosStartupLoader`, `ConversationsStartupLoader`, and `MessagesStartupLoader`.
- Added `MessageCacheStore` for background preload and instant chat open from cache.
- Wired realtime handlers to update inactive conversation message cache.
- Fixed onboarding profile completion to run the same critical warmup as cold start.
- Added `Docs/StartupLoading.md` and startup/cache unit tests.

## 2026-06-19

### Auth account lifecycle (verified)

- Confirmed end-to-end password reset magic link flow on staging: forgot password from `AuthView` → Resend email → Universal Link opens `ResetPasswordView` → `POST /auth/reset-password` → return to login with the new password.
- Confirmed account deletion UI in `ProfileSettingsView` remains wired to `DELETE /me/account`.
- Updated `Docs/EmailVerification.md` with password reset deep link notes, AASA path for `/auth/reset-password`, and current verified status.

### Profile API alignment + photos

- Added `isVisibleInDiscovery` support in `UserProfileDTO` and `UpsertProfileRequestBody` with safe decode default `true`.
- Added discovery visibility toggle in `ProfileSettingsView` (`Show my profile in discovery`) with immediate `PUT /profile/me`, optimistic UI, and rollback on error.
- Added profile photo DTOs in `Core/Models/ProfilePhotoModels.swift`.
- Added profile photo API requests in `Core/API/ProfilePhotoRequests.swift`:
  - `POST /profile/me/photos/upload-url`
  - `POST /profile/me/photos/uploads/:uploadID/complete`
  - `GET /profile/me/photos`
  - `PATCH /profile/me/photos/:photoID/primary`
  - `DELETE /profile/me/photos/:photoID`
  - `GET /profile/photos/:photoID/download-url`
- Added `ProfilePhotoService` and `ObjectStorageUploader` for direct `PUT` to presigned Object Storage URLs using exact backend headers (no JWT, no full signed URL logging).
- Added `ProfilePhotoImagePipeline` (resize to max 1024, JPEG ~0.8) and `ProfilePhotoStore` for runtime photo state.
- Replaced `ProfilePhotosPlaceholderView` with `ProfilePhotosView`:
  - 2-column progressive gallery up to 6 photos;
  - add cell only for the next available slot;
  - context menu: make primary / delete;
  - upload/list/primary/delete wired to backend.
- Wired `ProfileView` avatar to primary photo display and real upload flow through existing `AvatarCropEditorView`.
- Added `RemoteProfilePhotoView` with reload on expired `downloadUrl`.
- Added localized profile photo errors and UI strings in `Localizable.xcstrings`.
- Injected `ProfilePhotoStore` through `RootView` environment; reset store on `SessionStore.clearSession()`.
- Verified iOS build with `xcodebuild -scheme JustTwo -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/JustTwoDerivedData build`.

## 2026-06-23

### Server-synchronized photo order and avatar presentation

- Added `avatarPresentation` decoding to `ProfilePhotoDTO` using camelCase `offsetX`, `offsetY`, and `scale` fields.
- Added iOS API support for:
  - `PATCH /profile/me/photos/reorder`;
  - `PATCH /profile/me/photos/:photoID/presentation`.
- Changed the gallery source of truth from locally persisted order to backend `position` values.
- Connected drag-and-drop completion to the atomic backend reorder endpoint using the complete active photo ID list.
- Kept gallery position and `isPrimary` independent; primary changes still use their dedicated endpoint.
- Changed avatar rendering and editor initialization to use presentation returned in the primary photo DTO.
- Changed avatar save to persist normalized presentation on the backend.
- Changed new avatar uploads to upload the full prepared image first and save presentation separately, avoiding double crop/transform.
- Normalized outgoing avatar presentation to offsets `-2...2` and scale `1...5`.
- Preserved server-confirmed photo state when reorder or presentation requests fail.
- Added `Docs/ProfilePhotos.md` with DTOs, endpoint contracts, synchronization rules, security notes, and a manual smoke test.
- Manually verified gallery order and avatar presentation persistence.
- Verified Debug iOS Simulator build with `xcodebuild`; build succeeded.

## 2026-07-07

### Messenger local DB schema foundation (PR15A, after `50fdbaa`)

- Added SwiftData messenger persistence under `Core/Persistence/Messenger/`:
  - entities: conversation, message, attachment, reaction aggregate, receipt, sync metadata;
  - `MessengerLocalStore` facade + `SwiftDataMessengerLocalStore` implementation;
  - DTO mapping and privacy-safe snapshots (`LocalMessengerSnapshots.swift`).
- Extended `JustTwoApp.sharedModelContainer` schema with messenger `@Model` types; wired `MessengerLocalStore.configureShared(modelContainer:)`.
- Reaction storage uses per-message emoji aggregates (`count`, `reactedByMe`) aligned with backend DTOs.
- Does **not** persist signed `downloadUrl` / `uploadUrl`.
- UI still uses in-memory caches only (`MessengerLocalStorageFeatureFlags.isLocalReadEnabled = false`).
- Hardened logout local DB reset against fast re-login:
  - `SessionStore.clearSession()` → `scheduleLogoutReset()`;
  - `runCriticalWarmup()` → `await waitForLogoutReset()`;
  - `performReset()` awaits `resetAllMessengerData()`;
  - `MessengerLocalStore` session-generation guard blocks stale reads/writes during reset.
- Added messenger local-store diagnostics events in `MessengerDiagnostics.swift`.
- Added `JustTwoTests/MessengerLocalStoreTests.swift` and extended `AppStartupCoordinatorTests` for reset/wait coverage.
- Added `Docs/MessengerLocalStorage.md`; updated `Docs/StartupLoading.md` reset section.

## 2026-07-07 (PR15B)

### Cached messenger conversation list

- Enabled cache-first conversation list hydration via `MessengerConversationCacheService`.
- `ConversationListViewModel` loads local cache before REST; network failure keeps cached rows visible.
- REST success upserts conversations into `MessengerLocalStore`; delta/realtime patch local cache.
- Extended `LocalMessengerConversation` with denormalized lastMessage preview fields (no signed URLs).
- Added `ChatUIMapping.conversationPreview(from: LocalConversationSnapshot)`.
- Feature flag: `MessengerLocalStorageFeatureFlags.isCachedConversationListEnabled = true`.
- Message history UI remains REST/in-memory (`isLocalReadEnabled = false`).
- Added PR15B diagnostics events and `JustTwoTests/MessengerConversationCacheTests.swift`.
- Updated `Docs/MessengerLocalStorage.md`, `Docs/StartupLoading.md`, `Docs/Realtime.md`.

## 2026-07-07 (PR15C)

### Cached messenger messages per conversation + resilient chat loading

- Added `MessengerMessageCacheService` for local DB message hydrate/persist orchestration.
- `ChatViewModel` hydrates from `MessengerLocalStore` before REST; cached messages show immediately.
- `MessageCacheStore` persists REST/pagination to local DB; stale/cancelled loads ignored via `loadGeneration`.
- Fixed chat loading lifecycle: `isLoading` / `isLoadingOlderMessages` always terminate; network failure does not clear cache.
- Delta/realtime message handlers persist to local message cache.
- Added `ChatUIMapping.message(from: LocalMessageSnapshot)` and `ChatMessageAttachment.cached`.
- Feature flag: `MessengerLocalStorageFeatureFlags.isLocalReadEnabled = true`.
- Fixed offline/airplane mode hang: local DB hydrate before network, background REST when cache shown, `isAwaitingInitialMessagePage` simplified, delivered/read acks non-blocking.
- Updated `Docs/MessengerLocalStorage.md`, `Docs/StartupLoading.md`, `Docs/Realtime.md`.
- Out of scope: persistent cursor runtime, persistent outbox runner, full `MessengerSyncEngine`, backend changes.

## 2026-07-07 (PR15D)

### Offline-friendly splash and cache-first critical warmup

- Added `StartupSessionSnapshotStore` for persisted user/profile snapshot (Application Support JSON; no JWT/signed URLs).
- Splash hydrates cached session before network validation; recoverable network errors route to main when cache is usable.
- Split `AppStartupCoordinator` into critical local warmup (SwiftData conversation hydrate) and background network warmup (REST, photos, avatars, delta, realtime).
- Added `SessionConnectivityState`, `OfflineSessionBanner`, `StartupSessionValidationService` for background re-validation.
- `401` still clears session; network unavailable is not treated as invalid session.
- Added startup diagnostics events and `JustTwoTests/OfflineStartupTests.swift`.
- Updated `Docs/StartupLoading.md`, `Docs/MessengerLocalStorage.md`, `Docs/Realtime.md`.
- Deferred: PR15E (MessagesStartupLoader local-DB-first), PR15F (pop refresh removal, ack batching).

## 2026-07-07 (PR15E)

### Persistent media disk cache for message attachments

- Added `MessengerMediaDiskCache` + `MessengerMediaCacheService` (memory → disk → network → placeholder).
- Storage: `Application Support/JustTwo/MediaCache/attachments/<attachmentID>/thumb.jpg|full.jpg`.
- Extended `LocalMessengerAttachment` with disk availability metadata flags (no URLs/paths/bytes in SwiftData).
- Integrated `ChatImageBubbleView` and `ChatPhotoViewerView` with disk cache read/write.
- Delete message removes disk files; logout clears cache; background quota/LRU cleanup on startup.
- File protection `completeUntilFirstUserAuthentication`; excluded from iCloud backup.
- Added `Docs/MessengerMediaCache.md` and updated `Docs/MessengerLocalStorage.md`, `Docs/StartupLoading.md`, `Docs/Realtime.md`.
- Added `JustTwoTests/MessengerMediaDiskCacheTests.swift`.
- Out of scope: persistent outbox, outgoing media retry, sync cursor, backend changes.

## 2026-07-07 (PR15F)

### Messenger startup/request optimization

- `MessagesStartupLoader` local-DB-first: SwiftData hydrate → memory before REST preload.
- `MessengerCacheFreshnessPolicy` centralizes memory TTL (180s), list refresh TTL (120s), message freshness vs `lastMessageAt`.
- Chat open skips redundant `GET /messages` when cache fresh (`force:false`); manual refresh still forces REST.
- `ChatsView` no longer refreshes full conversation list on every chat pop.
- `NetworkPathMonitor.shouldSkipNetworkBecauseOffline` fail-fast for messages/conversations when offline is known.
- Conversation list delivery ack batch moved to background Task.
- Added PR15F diagnostics events and `JustTwoTests/MessengerRequestOptimizationTests.swift`.
- Updated `Docs/StartupLoading.md`, `Docs/MessengerLocalStorage.md`, `Docs/MessengerMediaCache.md`, `Docs/Realtime.md`.
- Out of scope: persistent outbox, sync cursor, backend changes.

## 2026-07-09 (PR16A)

### Persistent text outbox foundation

- Added `LocalMessengerOutboxItem` SwiftData entity (schema v3) for durable text send jobs with stable `clientMessageID`.
- Extended `MessengerLocalStore` with outbox CRUD, stale `sending` recovery, and logout reset via `resetAllMessengerData`.
- `MessengerOutbox` persists text jobs before pump, updates status on send/fail, deletes row on success.
- Added `MessengerOutboxProcessor` for relaunch recovery, chat rehydrate, manual retry, and network-restore auto-retry.
- `ChatViewModel` reconciles outbox on chat open; failed bubble retry routes through processor.
- Reconciliation clears outbox when REST/realtime/delta confirms same `clientMessageID`.
- Added privacy-safe outbox diagnostics events; message body never exported.
- Added `Docs/MessengerOutbox.md`, updated `Docs/MessengerLocalStorage.md`.
- Added `JustTwoTests/MessengerOutboxTests.swift`.
- **Manual smoke:** not run (checklist in PR16A report).
- Out of scope: image outbox, upload retry, full sync engine (PR16B/PR16C).

## 2026-07-09 (PR16B)

### Persistent image outbox + composer preview

- Composer image preview before Send (picker no longer auto-sends); X removes preview, keeps typed text.
- Image + optional comment sends as **one** `kind=image` message (`body` = caption).
- Added `LocalMessengerPendingMedia` (schema v4) + `MessengerPendingMediaStore` in Application Support.
- Extended `LocalMessengerOutboxItem` with `pendingMediaID`; image jobs use PR16A lifecycle.
- `ChatViewModel.sendComposerImage` durable ordering: persist file → SwiftData → bubble → clear composer → pump.
- `MessengerOutbox.registerPersistedImageEntry` + `rehydrateImageItem`; upload session refreshed on retry.
- `MessengerOutboxProcessor` rehydrates pending image bubbles + caption after relaunch.
- Success/logout clears outbox row + pending media file; no `uploadUrl`/`storageKey` persistence.
- Updated `Docs/MessengerOutbox.md`, `Docs/MessengerMediaCache.md`, `Docs/MessengerLocalStorage.md`.
- Added/extended `MessengerOutboxTests`, `MessengerPendingMediaStoreTests`, `OptimisticSendTests`.
- **Manual smoke:** not run (checklist in PR16B report).
- Out of scope: retry UI polish (PR16C), full sync engine.

## Notes

- Continue adding completed changes here after each meaningful update.
