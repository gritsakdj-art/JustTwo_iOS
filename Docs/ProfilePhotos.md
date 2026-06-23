# Profile Photos And Avatar Presentation

JustTwo iOS uses the authenticated profile photo API at:

```text
https://api.jtwo.online
```

The backend is the source of truth for:

* active profile photos;
* gallery order (`position`);
* primary/avatar selection (`isPrimary`);
* avatar presentation (`offsetX`, `offsetY`, `scale`).

Gallery order and primary status are independent. Reordering photos never implicitly changes the primary photo. The iOS UI may explicitly call both endpoints when the user drops a photo into the primary slot.

## Profile Photo DTO

All endpoints that return a complete photo use the same camelCase shape:

```json
{
  "id": "PHOTO_UUID",
  "position": 0,
  "isPrimary": true,
  "contentType": "image/jpeg",
  "byteSize": 482391,
  "width": 1024,
  "height": 1024,
  "downloadUrl": "https://storage.example/signed-url",
  "avatarPresentation": {
    "offsetX": 0.12,
    "offsetY": -0.05,
    "scale": 1.3
  },
  "createdAt": "2026-06-23T10:00:00Z",
  "updatedAt": "2026-06-23T10:05:00Z"
}
```

The backend always returns `avatarPresentation`. Photos without stored presentation use:

```json
{
  "offsetX": 0.0,
  "offsetY": 0.0,
  "scale": 1.0
}
```

Signed download and upload URLs are temporary and must never be persisted or logged in full.

## Supported Endpoints

All endpoints require:

```http
Authorization: Bearer <JWT_TOKEN>
```

### List photos

```http
GET /profile/me/photos
```

Response:

```json
{
  "photos": []
}
```

Only active photos are returned, sorted by `position ASC`. iOS replaces its runtime photo state with this response.

### Create and complete upload

```http
POST /profile/me/photos/upload-url
POST /profile/me/photos/uploads/:uploadID/complete
```

iOS requests a presigned upload, uploads the prepared JPEG directly to Object Storage using the exact returned method and headers, then completes the upload. Object Storage credentials are never available to the app.

The complete response is:

```json
{
  "photo": { "id": "PHOTO_UUID" }
}
```

The actual `photo` object uses the complete DTO shape above.

### Reorder gallery

```http
PATCH /profile/me/photos/reorder
Content-Type: application/json
```

Request:

```json
{
  "photoIds": [
    "PHOTO_UUID_2",
    "PHOTO_UUID_1",
    "PHOTO_UUID_3"
  ]
}
```

`photoIds` is the complete order of every active photo. It cannot contain duplicates, unknown IDs, deleted photos, foreign photos, or omit an active photo.

Response:

```json
{
  "photos": []
}
```

The returned photos are sorted by their new positions. `ProfilePhotoStore` replaces its state with this response. Drag preview remains local UI state, but the final order is committed to the backend before it becomes authoritative.

### Set primary photo

```http
PATCH /profile/me/photos/:photoID/primary
```

Response:

```json
{
  "photo": { "id": "PHOTO_UUID", "isPrimary": true }
}
```

Setting primary does not reset gallery position or avatar presentation.

### Update avatar presentation

```http
PATCH /profile/me/photos/:photoID/presentation
Content-Type: application/json
```

Request:

```json
{
  "offsetX": 0.12,
  "offsetY": -0.05,
  "scale": 1.3
}
```

Response:

```json
{
  "photo": { "id": "PHOTO_UUID" }
}
```

The transform describes how the original image is displayed inside the circular avatar viewport. The backend does not physically crop the object.

iOS normalizes values to the backend contract before sending:

```text
offsetX: -2.0...2.0
offsetY: -2.0...2.0
scale: 1.0...5.0
```

When the user selects a new avatar image, iOS uploads the full prepared image and then saves presentation for the newly created photo. This avoids applying the crop twice.

### Delete and refresh download URL

```http
DELETE /profile/me/photos/:photoID
GET /profile/photos/:photoID/download-url
```

Deleting a photo removes it from subsequent active-photo lists. The download URL endpoint is used to refresh expired signed URLs.

## iOS Implementation

Relevant files:

```text
Core/Models/ProfilePhotoModels.swift
Core/API/ProfilePhotoRequests.swift
Core/Services/ProfilePhotoService.swift
Core/Session/ProfilePhotoStore.swift
Shared/Helpers/AvatarCropGeometry.swift
Shared/Views/Profile/ProfilePhotosView.swift
Shared/Views/Profile/ProfileView.swift
Shared/Views/Profile/AvatarCropEditorView.swift
```

Runtime behavior:

* `ProfilePhotoDTO.avatarPresentation` is decoded from every complete photo response;
* `ProfilePhotoStore.galleryPhotos` follows server `position` order;
* successful reorder replaces the entire photo array with the server response;
* successful presentation update replaces the matching photo DTO;
* avatar rendering and editor initialization use the primary photo's server presentation;
* local `UserDefaults` order/crop values are not the authoritative state;
* network errors keep the last confirmed server state and are shown through the existing localized error UI.

## Manual Smoke Test

1. Log in and upload three photos.
2. Reorder them with drag and drop.
3. Leave and reopen the gallery; verify the same order.
4. Restart the app; verify the order again.
5. Log in on another simulator/device and verify the same order.
6. Set another photo as primary and verify gallery order remains stored independently.
7. Move and zoom the avatar, then save.
8. Reopen the avatar editor and verify the same transform.
9. Restart and verify the avatar again.
10. Log in on another simulator/device and verify the same presentation.
11. Delete a photo and reorder the remaining photos.
12. Verify deleted photos never return to the gallery.

Expected API validation failures use the standard backend error envelope, commonly `validation_failed` or `photo_not_found` for invalid photo mutations.
