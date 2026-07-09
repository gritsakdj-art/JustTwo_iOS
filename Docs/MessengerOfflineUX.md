# Messenger Offline UX (PR18)

## Purpose

PR18 polishes user-facing offline, cache, sync, and outbox states on top of PR15–PR17 mechanics. It does **not** change sync/outbox architecture.

## User-facing states

| State | User sees |
| --- | --- |
| Online, up to date | Normal UI, optional “Updated just now” in chats list |
| Refreshing | Subtle “Refreshing…” strip; cached list/messages stay visible |
| Offline, saved data | Global banner + chat/list hints |
| Offline, no saved data | Empty state explaining internet is needed |
| Refresh failed | Banner/strip: saved data still available |
| Outbox waiting | “Will send when you're back online.” |
| Outbox failed | “Failed to send. Tap to retry.” |

Tone is short and calm — no technical jargon (no “delta sync”, “cursor”, “NetworkPath”).

## Architecture

- `MessengerConnectivityPresentationState` + `MessengerConnectivityPresentationResolver` — pure mapping from signals to presentation state.
- `MessengerUXStatusStore` — `@Observable` coordinator combining network path (debounced), `SessionStore`, `MessengerSyncEngine`, list refresh flags.
- `OfflineSessionBanner` — renders `MessengerBannerPresentation` in `MainTabView`.
- `MessengerSubtleStatusStrip` — non-blocking status in chats list and chat screen.

### Inputs

- `NetworkPathMonitor` (debounced offline in UX store)
- `SessionConnectivityState`
- `MessengerSyncEngine.state` (`@Observable` since PR18)
- Conversation/message cache availability
- List/chat network refresh flags
- Last refresh failure flags

## Cached data behavior

- Cached conversations/messages remain visible during refresh and after refresh failure.
- No full-screen loader replaces cached content.
- `isLoading` spinner only when there is nothing cached to show yet.

## No-cache empty states

**Chats list (offline, no saved chats)**

- EN: “No saved chats” / “Connect to the internet to load your chats.”
- RU: “Нет сохранённых чатов” / “Подключитесь к интернету…”

**Chat (offline, no saved messages)**

- EN: “No saved messages” / “Connect to the internet to load this chat.”
- RU: “Нет сохранённых сообщений” / “Подключитесь к интернету…”

## Sync / refresh states

- Global banner: offline showing cache, connection restored refreshing, refresh failed.
- Chats/chat: subtle strip for refreshing, offline stale hint, refresh failed with cache.
- Pull-to-refresh offline: fails fast, cache preserved, no endless spinner.

## Outbox wording (PR18)

| State | EN | RU |
| --- | --- | --- |
| Waiting (offline) | Will send when you're back online. | Будет отправлено, когда появится интернет. |
| Waiting (online) | Waiting for network | Ожидает сеть |
| Sending | Sending… | Отправляем… |
| Uploading photo | Uploading photo… | Загружаем фото… |
| Retrying | Retrying… | Повторяем отправку… |
| Failed | Failed to send. Tap to retry. | Не удалось отправить. Нажмите, чтобы повторить. |

## Network restore

1. Offline banner (debounced show, immediate hide on restore).
2. Short “Connection restored. Refreshing…” global banner (~4s).
3. Existing sync engine / outbox retry runs unchanged.
4. Returns to normal when sync completes.

## Diagnostics summary

Export prepends a privacy-safe summary:

- connectivity / presentation / sync engine state
- `lastAppliedRevision`, `lastSuccessfulSyncAt`
- outbox pending/failed counts, pending media count
- conversation cache availability

Never includes: message body, caption, JWT, signed URLs, absolute paths, storage keys.

## Privacy rules

Same as PR16–PR17: diagnostics and UI must not expose secrets or message content.

## Known limitations

- “Updated X min ago” only when `lastSuccessfulSyncAt` exists; shown subtly in chats list diagnostics path.
- Per-chat cache flag in diagnostics is list-scoped only unless chat is open.
- UI tests not included; presentation mapping covered in `MessengerOfflineUXTests`.

## Follow-ups

- **PR19** — media cache management screen
- **PR20** — backend retention/metrics
