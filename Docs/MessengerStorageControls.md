# Messenger Storage Controls (PR19)

User-facing and diagnostic controls for messenger media disk usage.

## Settings UI

**Profile → General settings → Storage** (`GeneralSettingsView`):

| Row | Shows |
|-----|-------|
| Media cache | Confirmed cache size (formatted via `ByteCountFormatter`) |
| Pending uploads | Pending outgoing image bytes (separate from confirmed cache) |
| Clear media cache | Action with confirmation dialog |

### Clear confirmation copy

- **EN:** “Clear media cache? Photos from messages will be removed from this device, but will stay in chats and download again when opened. Unsent photos will not be affected.”
- **RU:** «Очистить кэш медиа? Фотографии из сообщений будут удалены с устройства, но останутся в чатах и загрузятся заново при открытии. Неотправленные фото затронуты не будут.»

## API surface

| API | Purpose |
|-----|---------|
| `MessengerMediaCacheControls.inventory()` | Bytes/counts for confirmed + pending |
| `MessengerMediaCacheControls.trimNow()` | LRU trim confirmed cache to soft limit |
| `MessengerMediaCacheControls.clearConfirmedMediaCache()` | Remove all confirmed files + metadata flags |
| `MessengerMediaCacheControls.runCleanupIfNeeded()` | Best-effort automatic trim |
| `MessengerStorageFormatting.string(for:)` | Localized byte formatting |

## Automatic trim triggers

- After startup background warmup
- After successful media store when over soft limit
- App entering background (best-effort)
- Orphan cleanup runs as part of trim

## Diagnostics export

`MessengerDiagnostics.exportTextForClipboard()` (async) appends a privacy-safe media section:

- confirmed thumbnail/full counts and bytes
- pending outgoing count and bytes
- soft/hard limits, over-limit bytes
- last trim timestamp / deleted bytes / deleted count
- orphan cleanup counts

Never exports absolute paths, signed URLs, storage keys, JWT, or message body/caption.

## Manual smoke

See PR19 report checklist in project notes / MessengerMediaCache.md.

## Related

- [Messenger Media Cache](MessengerMediaCache.md)
- [Messenger Outbox](MessengerOutbox.md) — pending media boundary
- [Messenger Offline UX](MessengerOfflineUX.md) — offline placeholder after clear
