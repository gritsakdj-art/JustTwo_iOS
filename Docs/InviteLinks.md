# Invite Links And QR Flow

JustTwo iOS supports direct chat invites through server-issued Universal Links and client-generated QR codes.

Staging API:

```text
https://api.jtwo.online
```

Canonical invite URL format:

```text
https://api.jtwo.online/invite/{token}
```

The iOS client never fabricates invite tokens. It always uses `inviteURL` returned by the backend.

## Product Flow

### Create and share

1. User opens **Chats** and taps `+`.
2. `InviteLinkView` calls `POST /invites/direct`.
3. The screen shows:
   - QR code generated locally from `inviteURL`;
   - circular `ActionButton` actions for copy link, share link, share QR image, and refresh;
   - a bottom section to paste someone else's invite link.
4. Sharing uses `ActivityShareSheet` with the server URL or rendered QR image.

### Open from Universal Link

1. App receives `https://api.jtwo.online/invite/{token}`.
2. `DeepLinkParser` extracts the token.
3. `AppDeepLinkHandler` routes through `AppRouter.handleIncomingInvite`.
4. If the user is authenticated and email-verified, `InvitePreviewView` opens as a full-screen cover from `DiscoverView`.
5. If the user is logged out, the app routes to auth and keeps `pendingInviteToken` until startup completes.

### Preview and accept

`InvitePreviewView` loads creator profile data through:

```http
GET /invites/{token}/preview
```

Actions:

* **Accept** → `POST /invites/{token}/accept`, then open the created conversation in **Chats**.
* **Decline** → dismiss preview only.
* **Block** → `POST /profiles/{profileID}/block`, then dismiss preview.

Accept success returns both `connection` and `conversation`. `AppRouter.openChatAfterInviteAccept` switches to the Chats tab and opens `PrivateChatView`.

### Paste link manually

`InviteLinkView` accepts pasted text or clipboard content. Token extraction supports:

* full `https://api.jtwo.online/invite/...` URLs;
* host-prefixed fragments;
* invite URLs embedded in longer pasted text.

Pasted previews use `fullScreenCover(item:)` so the preview screen is not presented with an empty white container.

## Backend Endpoints

```http
POST /invites/direct
GET /invites/{token}/preview
POST /invites/{token}/accept
DELETE /invites/{inviteID}
POST /profiles/{profileID}/block
```

`POST /invites/direct` optional body:

```json
{
  "expiresInSeconds": 86400,
  "maxUses": 1
}
```

Invite DTO fields used by iOS:

```json
{
  "id": "INVITE_UUID",
  "type": "direct",
  "status": "active",
  "inviteURL": "https://api.jtwo.online/invite/server-token",
  "expiresAt": "2026-06-19T10:00:00Z",
  "maxUses": 1,
  "useCount": 0,
  "createdAt": "2026-06-18T10:00:00Z"
}
```

## Deep Link Parsing

Supported host:

```text
api.jtwo.online
```

Parser entry points:

* `DeepLinkParser.parse(_:)` for Universal Links;
* `DeepLinkParser.inviteToken(from:)` for pasted strings and URLs.

Auth and invite links share one handler:

* `Core/DeepLinks/DeepLinkParser.swift`
* `Core/DeepLinks/AppDeepLinkHandler.swift`

`EmailVerificationDeepLinkHandler` delegates non-auth invite URLs to `AppDeepLinkHandler`.

## Key iOS Files

```text
JustTwo/
├── Core/
│   ├── API/MessengerRequests.swift
│   ├── API/ProfileBlockRequests.swift
│   ├── DeepLinks/DeepLinkParser.swift
│   ├── DeepLinks/AppDeepLinkHandler.swift
│   ├── Invites/QRCodeGenerator.swift
│   ├── Invites/InviteErrorMapper.swift
│   └── Services/
│       ├── MessengerService.swift      # InviteService
│       └── ProfileBlockService.swift
├── Router/AppRouter.swift
└── Shared/
    ├── Components/ActivityShareSheet.swift
    └── Views/Invites/
        ├── InviteLinkView.swift
        ├── InviteLinkViewModel.swift
        ├── InvitePreviewView.swift
        └── InvitePreviewViewModel.swift
```

## Localization And Errors

Invite UI strings live in `Localizable.xcstrings` for:

* English
* Russian
* German
* Spanish
* French
* Italian
* Arabic

Mapped backend error codes:

* `invalid_invite_token`
* `invite_expired`
* `invite_revoked`
* `invite_already_used`
* `cannot_accept_own_invite`
* privacy restriction errors for blocked or hidden profiles

## Tests

`JustTwoTests` target covers:

* `DeepLinkParserTests` — invite URL and pasted text parsing;
* `QRCodeGeneratorTests` — QR rendering from invite URL;
* `InviteLinkViewModelTests` — server `inviteURL` resolution.

Run:

```bash
xcodebuild -scheme JustTwo -destination 'platform=iOS Simulator,id=SIMULATOR_ID' test
```

## Universal Links Checklist

Associated domain:

```text
applinks:api.jtwo.online
```

Required AASA path:

```text
/invite/*
```

The invite link must resolve to the installed app on device. If Universal Links are not configured yet, users can still paste the URL manually from `InviteLinkView`.

## Chat UI Notes

Related chat polish shipped with this flow:

* `PrivateChatView` shows the partner avatar in the navigation bar trailing slot.
* `ChatBubbleView` enforces a minimum bubble width so timestamps stay inside the bubble.
* `ChatPatternBackground` tiles `Assets.xcassets/ChatPattern` over `discoverBackgroundGradient` with `brandPrimaryGradient` at 25% opacity.
