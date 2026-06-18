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

## Notes

- Continue adding completed changes here after each meaningful update.
