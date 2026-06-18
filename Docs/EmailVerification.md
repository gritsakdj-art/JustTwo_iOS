# Email Verification

JustTwo iOS supports the backend email verification flow introduced in backend PR2/PR3.

Staging API:

```text
https://api.jtwo.online
```

Current staging mode:

```text
EMAIL_PROVIDER=resend
EMAIL_VERIFICATION_REQUIRED=false
```

This means the current iOS flow remains compatible:

* register still returns JWT;
* login still works for unverified users;
* verification email is still delivered through Resend;
* `/me` returns `emailVerified` and `emailVerifiedAt`.

## Backend Endpoints

```http
POST /auth/register
POST /auth/login
GET /me
POST /auth/resend-verification
GET /auth/verify-email?token=...
```

## Register Behavior

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

## Login Behavior

If backend returns:

```text
email_not_verified
```

iOS shows `CheckEmailView` for the login email instead of a generic error.

## Magic Links

Expected production link:

```text
https://api.jtwo.online/auth/verify-email?token=...
```

iOS parses:

* host: `api.jtwo.online`;
* path: `/auth/verify-email`;
* query item: `token`.

The raw token is not logged, stored, shown in UI, or sent to analytics.

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
          "/auth/verify-email*"
        ]
      }
    ]
  }
}
```

Simulator note:

* universal links can be inconsistent in Simulator;
* use real-device testing for final validation;
* app-side parsing can be validated by passing a URL into `EmailVerificationDeepLinkHandler` during development.
