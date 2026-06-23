# Auth Deep Links

JustTwo iOS supports backend auth deep links for:

* email verification;
* password reset.

Staging API:

```text
https://api.jtwo.online
```

Current staging mode:

```text
EMAIL_PROVIDER=resend
EMAIL_VERIFICATION_REQUIRED=false
```

## Email Verification

### Compatibility mode

* register still returns JWT;
* login still works for unverified users;
* verification email is delivered through Resend;
* `/me` returns `emailVerified` and `emailVerifiedAt`.

### Backend endpoints

```http
POST /auth/register
POST /auth/login
GET /me
POST /auth/resend-verification
GET /auth/verify-email?token=...
POST /auth/verify-email-session
```

### Register behavior

Compatibility mode:

```text
register returns token + user
```

iOS behavior:

* save JWT as before;
* keep current profile setup flow working;
* store `currentUser.emailVerified`.

Future required-verification mode:

```json
{
  "success": true,
  "message": "Registration successful. Please check your email to verify your account.",
  "verificationRequired": true
}
```

iOS behavior:

* do not save token;
* store pending email locally in memory;
* show `CheckEmailView`;
* let the user resend the email or return to login.

### Login behavior

If backend returns:

```text
email_not_verified
```

iOS shows `CheckEmailView` for the login email instead of a generic error.

### Verification magic link

Expected link:

```text
https://api.jtwo.online/auth/verify-email?token=...
```

iOS flow:

* `RootView.onOpenURL` → `EmailVerificationDeepLinkHandler`;
* parse host `api.jtwo.online`, path `/auth/verify-email`, query `token`;
* open `EmailVerificationResultView` or error state.

The raw token is not logged, stored in persistent storage, shown in UI, or sent to analytics.

## Password Reset

Status on staging:

```text
verified end-to-end on iOS (forgot password → email → Universal Link → ResetPasswordView → login with new password)
```

### Backend endpoints

```http
POST /auth/forgot-password
POST /auth/reset-password
```

Browser fallback only (does not reset password or consume token):

```http
GET /auth/reset-password?token=...
```

### Forgot password UX

On login screen:

* after `invalid_credentials`, iOS shows a forgot-password action;
* user submits email in a sheet;
* iOS calls `POST /auth/forgot-password`;
* backend returns generic success regardless of account existence.

### Reset magic link

Expected link:

```text
https://api.jtwo.online/auth/reset-password?token=...
```

iOS flow:

* `RootView.onOpenURL` → `EmailVerificationDeepLinkHandler`;
* parse host `api.jtwo.online`, path `/auth/reset-password`, query `token`;
* open `ResetPasswordView(token:)`;
* user enters and confirms new password;
* iOS calls `POST /auth/reset-password`;
* on success: clear local session and return to `AuthView`.

Missing/invalid token opens `ResetPasswordView` error state.

The raw reset token is not logged, stored in persistent storage, or shown in UI.

### iOS files

```text
Shared/Views/Auth/AuthView.swift
Shared/Views/Auth/AuthViewModel.swift
Shared/Views/Auth/ResetPasswordView.swift
Core/DeepLinks/EmailVerificationDeepLinkHandler.swift
Core/API/AuthRequests.swift
Core/Services/AuthService.swift
Router/AppScreen.swift
Router/AppRouter.swift
Router/RootRouterView.swift
```

## Universal Links Checklist

Xcode / Apple Developer:

* add Associated Domains capability;
* add `applinks:api.jtwo.online`.

Current project identifiers:

```text
Bundle ID: pro.sda.justtwo.JustTwo
Team ID: TQ873YGCDK
```

Backend/domain must serve Apple App Site Association:

```text
https://api.jtwo.online/.well-known/apple-app-site-association
```

Content-Type:

```text
application/json
```

Example AASA:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appIDs": [
          "TQ873YGCDK.pro.sda.justtwo.JustTwo"
        ],
        "components": [
          {
            "/": "/auth/verify-email",
            "comment": "Email verification links"
          },
          {
            "/": "/auth/reset-password",
            "comment": "Password reset links"
          }
        ]
      }
    ]
  }
}
```

Legacy `paths` variant:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TQ873YGCDK.pro.sda.justtwo.JustTwo",
        "paths": [
          "/auth/verify-email*",
          "/auth/reset-password*"
        ]
      }
    ]
  }
}
```

Testing notes:

* Universal Links can be inconsistent in Simulator;
* use real-device testing for final validation;
* app-side parsing can be validated by passing a URL into `EmailVerificationDeepLinkHandler` during development;
* if a device keeps old association data after AASA changes, delete and reinstall the app.
