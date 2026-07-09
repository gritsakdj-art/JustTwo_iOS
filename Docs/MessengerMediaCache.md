# Messenger Media Disk Cache (PR15E)

Persistent on-disk cache for **confirmed/received** message image attachments.

## Goal

If an image attachment was already loaded/viewed/downloaded, it survives app relaunch and is available offline from disk cache.

## Scope

### In scope (PR15E)

- Disk cache for confirmed/received image attachments with server `attachmentID`
- Thumbnail variant for chat bubbles; full variant for photo viewer when downloaded
- Stable cache key: `attachmentID` / `localCacheKey` (never signed URL)
- Layering: **memory → disk → network → placeholder**
- Cleanup on delete, quota/LRU, logout reset
- File protection + iCloud backup exclusion
- Privacy-safe diagnostics + tests

### Out of scope (PR15E)

- Persistent outgoing outbox / failed upload retry (**PR16B** — separate pending media store)
- Persistent sync cursor / full sync engine (**PR17**)
- Storing signed URLs, upload URLs, storage keys, image bytes, or absolute paths in SwiftData
- Startup preload optimization beyond local-DB-first message hydrate (**PR15F**)

## Architecture

```text
ChatImageBubbleView / ChatPhotoViewerView
  └─ MessengerMediaCacheService
        ├─ ChatMessageImageCache (memory)
        ├─ MessengerMediaDiskCache (Application Support)
        ├─ ImageDownloadClient (network)
        └─ MessengerLocalStore (attachment media metadata flags)

AppStartupCoordinator.runBackgroundNetworkWarmup
  └─ MessengerMediaCacheService.runCleanupIfNeeded (background)

Logout reset
  └─ MessengerMediaCacheService.clearAll
```

## PR16B boundary — pending outgoing media (not confirmed cache)

PR16B adds a **separate** on-disk store for **outgoing** images waiting to upload:

```text
Application Support/JustTwo/MessengerPendingMedia/<pendingMediaID>/<clientMessageID>.jpg
```

| | PR15E confirmed cache | PR16B pending outgoing |
|--|----------------------|------------------------|
| Purpose | Received/confirmed attachments | Outbox upload retry |
| Key | `attachmentID` | `pendingMediaID` / `clientMessageID` |
| SwiftData | `LocalMessengerAttachment` flags | `LocalMessengerPendingMedia` metadata |
| Cleared on | Delete message, quota, logout | Send success, cancel, logout |
| Signed URLs | Ephemeral network only | Never persisted |

Pending outgoing files are **not** inserted into PR15E `MediaCache/` before server confirmation. After success, pending file is deleted; confirmed bubble loads via normal attachment/cache paths.

**PR16C:** User cancel/delete on failed/pending image also deletes the pending media file via `deleteOutboxItem` — confirmed PR15E cache is unaffected.

See [Messenger Outbox](MessengerOutbox.md) for composer preview, retry pipeline, and cleanup rules.

### Components

| Component | Path |
|-----------|------|
| `MessengerMediaDiskCache` | `Core/Persistence/Messenger/Media/MessengerMediaDiskCache.swift` |
| `MessengerMediaCacheService` | `Core/Persistence/Messenger/Media/MessengerMediaCacheService.swift` |
| `MessengerMediaVariant` | `thumbnail`, `full` |
| `MessengerMediaCacheCleanupPolicy` | quota defaults |

## Storage layout

```text
Application Support/JustTwo/MediaCache/attachments/<attachmentID>/
  thumb.jpg
  full.jpg
```

- `attachmentID` is sanitized before use as a path component
- Pending optimistic IDs (`local-*`) are rejected
- No signed URL / storage key used as cache key

## SwiftData metadata (`LocalMessengerAttachment`)

Persisted flags (no absolute paths, no URLs):

| Field | Purpose |
|-------|---------|
| `hasLocalThumbnail` | Bubble can render offline |
| `hasLocalFullImage` | Viewer can render full offline |
| `localThumbnailByteSize` | Diagnostics / quota hints |
| `localFullByteSize` | Diagnostics / quota hints |
| `mediaCachedAt` | First successful disk store |
| `mediaLastAccessedAt` | Updated on disk hit |

Metadata is preserved across attachment re-upserts when `attachmentID` is unchanged.

## Load flow

```text
1. UI receives image attachment with attachmentID/localCacheKey
2. Memory cache hit → render
3. Disk cache hit → hydrate memory → render → update lastAccessedAt
4. Disk miss + fresh downloadURL → network load → store disk + memory → render
5. Disk miss + no downloadURL → safe placeholder / failed state (no crash)
```

### Variant strategy

| Surface | Preferred | Fallback |
|---------|-----------|----------|
| Chat bubble | `thumbnail` | `full` |
| Photo viewer | `full` | `thumbnail` |

Bubble network downloads are stored as `thumbnail`. Viewer network downloads are stored as `full`.

## Delete / cleanup

### Message delete

When a message is tombstoned:

1. SwiftData attachment rows removed (PR15C behavior)
2. Disk files removed for affected `attachmentID`
3. SwiftData media flags cleared
4. In-memory `ChatMessageImageCache` entry removed

### Quota / LRU (PR19 update)

Default policy (`MessengerMediaCacheCleanupPolicy.default`):

| Setting | Value |
|---------|-------|
| Soft limit (`targetBytesAfterCleanup`) | 200 MB |
| Hard limit (`maxBytes`) | 300 MB |
| `maxAgeDays` | 90 |

Triggers:

- Background task after startup network warmup
- After store when total size exceeds soft limit
- App entering background (via `MessengerMediaCacheService.runCleanupIfNeeded`)
- Manual trim from storage controls (optional)

Trim order:

1. Orphan files not referenced by any `LocalMessengerAttachment.localCacheKey`
2. Files older than `maxAgeDays`
3. LRU **full** variants first until under soft limit
4. LRU **thumbnail** variants only if still over soft limit

Disk hits update file modification time (used for LRU) and SwiftData `mediaLastAccessedAt`.

**PR19 boundary:** Pending outgoing media in `MessengerPendingMedia/` is **never** trimmed or cleared by confirmed-cache LRU/trim.

## PR19 — Media cache controls

### Inventory (`MessengerMediaCacheControls.inventory`)

Non-blocking scan of confirmed disk cache + pending outgoing store:

| Field | Meaning |
|-------|---------|
| `confirmedThumbnailBytes` / `confirmedFullBytes` | Variant breakdown |
| `confirmedTotalBytes` / `confirmedFileCount` | Confirmed cache total |
| `pendingOutgoingBytes` / `pendingOutgoingFileCount` | Outbox upload files (separate directory) |
| `totalMessengerMediaBytes` | Confirmed + pending |
| `orphanConfirmedFileCount` / `orphanConfirmedBytes` | Unreferenced confirmed files |
| `cacheSoftLimitBytes` / `cacheHardLimitBytes` | Policy limits |
| `overLimitBytes` | Bytes above soft limit |

No absolute paths, signed URLs, or image decoding during inventory.

### Clear confirmed media cache

`MessengerMediaCacheControls.clearConfirmedMediaCache()`:

1. Removes all files under `MediaCache/attachments/`
2. Clears SwiftData confirmed media flags via `clearAllConfirmedMediaCacheMetadata()`
3. Clears in-memory `ChatMessageImageCache`
4. **Does not** delete `MessengerPendingMedia/` files or outbox rows
5. **Does not** delete messages/conversations

User control: **Settings → Storage → Clear media cache** (confirmation required, RU/EN).

After clear: bubbles/viewer show placeholder; online re-download uses ephemeral signed URLs; offline shows “Photo unavailable offline” when no local file and no URL.

### Components (PR19)

| Component | Path |
|-----------|------|
| `MessengerMediaCacheControls` | `Core/Persistence/Messenger/Media/MessengerMediaCacheControls.swift` |
| `MessengerMediaCacheInventory` | `Core/Persistence/Messenger/Media/MessengerMediaCacheInventory.swift` |
| `MessengerStorageFormatting` | `Shared/Utilities/MessengerStorageFormatting.swift` |
| Storage UI | `Shared/Views/Profile/GeneralSettingsView.swift` |

See [Messenger Storage Controls](MessengerStorageControls.md).

## Security / privacy

- `FileProtectionType.completeUntilFirstUserAuthentication` on cache files/directories
- `isExcludedFromBackup = true` (recoverable from backend; not backed up to iCloud)
- Diagnostics: sanitized `attachmentID`, `variant`, `byteSize`, `durationMs` only
- Never log/export: `downloadUrl`, `uploadUrl`, JWT, Bearer, storage keys, absolute paths, message body, raw image bytes

## Diagnostics events

`messengerMediaDiskCacheLookupStarted`, `Hit`, `Miss`, `ReadFailed`, `StoreStarted`, `StoreSucceeded`, `StoreFailed`, `Removed`, `CleanupStarted`, `CleanupSucceeded`, `BackupExcluded`, `FileProtectionApplied`

## Manual smoke checklist

1. **Seed cache:** open chat with image online → kill app → relaunch → image appears quickly
2. **Offline:** load image online once → airplane mode → relaunch → bubble shows cached image
3. **Viewer:** tap cached image offline → no crash (thumbnail or full)
4. **Disk miss:** image never loaded + offline → placeholder, no endless spinner
5. **Delete:** load image → delete message → relaunch → image does not reappear
6. **Outgoing confirmed:** send image online → confirm → relaunch → bubble uses disk if previously stored
7. **Cleanup:** app launch after large cache → no crash; recent media remains under quota
8. **Privacy:** export diagnostics → no signed URLs / tokens / local paths
9. **PR19 clear:** Settings → Clear media cache → confirmed files gone, pending uploads preserved, messages remain
10. **PR19 offline after clear:** airplane mode → placeholder / “Photo unavailable offline”, no endless spinner

## Related docs

- [Messenger Local Storage](MessengerLocalStorage.md)
- [Startup Loading](StartupLoading.md)
- [Realtime](Realtime.md)
