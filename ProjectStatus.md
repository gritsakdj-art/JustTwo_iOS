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

## Notes

- Continue adding completed changes here after each meaningful update.
