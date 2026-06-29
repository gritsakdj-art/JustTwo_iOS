# Push Notifications

## Scope

PR1 covers only iOS APNs registration foundation.

Implemented:
- APNs permission request
- APNs device token registration
- installationId stored in Keychain
- token sync with backend `/push/devices`
- best-effort unregister on logout via `/push/devices/current`
- minimal notification center delegate
- environment detection: sandbox for Debug, production for Release/TestFlight/App Store

Not included in PR1:
- backend PushDevice model/migration
- Vapor APNs provider
- push delivery from backend
- messenger push dispatch
- badge count
- notification preferences
- notification tap routing
- Firebase/FCM
- Android support

## Apple Developer setup

Manual steps:
1. Open Apple Developer Portal.
2. Select JustTwo Bundle ID.
3. Enable Push Notifications.
4. In Xcode target Signing & Capabilities:
   - add Push Notifications;
   - add Background Modes;
   - enable Remote notifications.
5. Create APNs Auth Key `.p8`.
6. Save:
   - Key ID;
   - Team ID;
   - Bundle ID / APNs topic;
   - `.p8` private key for backend PR.

## APNs environments

Debug builds use sandbox APNs.
TestFlight and App Store builds use production APNs.

The app sends `environment` to backend:
- `sandbox` for DEBUG;
- `production` for non-DEBUG.

## Device token lifecycle

- APNs token can change.
- The app should sync token after login/session restore.
- The app should sync token again when APNs returns a new token.
- Full token must not be logged.

## installationId

- Generated once per app installation.
- Stored in Keychain.
- Not deleted on logout.
- Used to identify a concrete app installation independently from userId.

## Backend endpoints expected by PR1

`POST /push/devices`

`DELETE /push/devices/current`

Backend implementation is expected in PR2.
If endpoints are unavailable, the app should not break user session.

## Privacy

- Do not log full APNs device token.
- Push message preview should be controlled later by notification preferences.
- Default future payloads should avoid exposing message text on lock screen.

## Future PRs

PR2:
- backend PushDevice model/migration;
- notification preferences;
- push device endpoints.

PR3:
- Vapor APNs provider;
- test push endpoint;
- delivery logs;
- APNs error handling.

PR4:
- messenger push integration;
- message.created notification intent;
- presence-aware delivery;
- badge count.

PR5:
- notification tap routing to conversation;
- foreground presentation rules;
- pending route after cold start.
