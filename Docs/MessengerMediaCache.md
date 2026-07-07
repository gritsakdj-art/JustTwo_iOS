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

### Out of scope

- Persistent outgoing outbox / failed upload retry (**PR16**)
- Persistent sync cursor / full sync engine (**PR17**)
- Storing signed URLs, upload URLs, storage keys, image bytes, or absolute paths in SwiftData
- Startup preload optimization

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

### Quota / LRU

Default policy (`MessengerMediaCacheCleanupPolicy.default`):

| Setting | Value |
|---------|-------|
| `maxBytes` | 300 MB |
| `targetBytesAfterCleanup` | 240 MB |
| `maxAgeDays` | 90 |

Triggers:

- Background task after startup network warmup
- After store when total size exceeds quota

Cleanup removes:

1. Orphan files not referenced by any `LocalMessengerAttachment.localCacheKey`
2. Files older than `maxAgeDays` (directory mtime scan)
3. LRU oldest directories when over quota

**Limitation:** LRU uses filesystem modification time at cleanup time, not `mediaLastAccessedAt`. Disk hits update SwiftData `mediaLastAccessedAt` for future enhancements but do not currently touch file mtimes; cleanup may therefore evict recently viewed media if quota pressure occurs before the file mtime changes.

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

## Related docs

- [Messenger Local Storage](MessengerLocalStorage.md)
- [Startup Loading](StartupLoading.md)
- [Realtime](Realtime.md)
