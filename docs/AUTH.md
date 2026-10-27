# Sign-in and accounts

Designing needs an account, because the free designs and the subscription are counted
per account on the server. The app offers two ways in; App Store guideline 4.8 requires
Sign in with Apple once any third-party sign-in (Google) is offered.

## Sign in with Apple

1. `SessionStore` builds an `ASAuthorizationAppleIDProvider` request with the name and
   email scopes.
2. iOS shows Apple's sheet; on success it returns an identity token (a JWT signed by
   Apple) and an authorisation code.
3. The app sends them to `POST /auth/apple/callback`. The server verifies the token's
   signature against Apple's public keys (`https://appleid.apple.com/auth/keys`, cached
   and re-fetched when Apple rotates them) and checks that the audience is the app's
   bundle id, then creates or finds the account and returns Alma's own tokens.

The capability is declared in `Alma.entitlements` (`com.apple.developer.applesignin`).

## Google sign-in (OAuth 2.0 with PKCE)

No Google SDK: the app uses `ASWebAuthenticationSession`, Apple's secure in-app browser
sheet, as recommended for native apps (RFC 8252).

1. The app makes a random `code_verifier` and its SHA-256 `code_challenge` (CryptoKit),
   per PKCE (RFC 7636).
2. It opens Google's authorisation page with the iOS client id, the challenge
   (`S256`) and a redirect to the app's reversed-client-id URL scheme (declared in
   `Info.plist`).
3. Google redirects back with an authorisation code. The app sends the code and the
   verifier to `POST /auth/google/callback`; the server exchanges them with Google and
   returns Alma's tokens.

Because of PKCE, an intercepted code is useless without the verifier, which never leaves
the device until the exchange. The iOS client id is public by design; there is no
client secret in the app.

## Session

- Alma's access token lasts 15 minutes; the refresh token (30 days) renews it
  (`POST /auth/refresh`). On a 401 the app refreshes once and retries. Refresh tokens
  rotate on every use, and reusing an old one revokes all of the user's sessions.
- Tokens live in the Keychain (`Keychain.swift`) with
  `kSecAttrAccessibleAfterFirstUnlock`, scoped to this app.
- Signing out clears the Keychain and any half-finished wizard, so the next user never
  sees the previous user's photo.

## Deleting the account

The menu on the photo screen (`UploadView`) has "Delete account", with a confirmation (App Store guideline 5.1.1(v)). For Apple accounts the
app first re-confirms with Apple so the server can revoke the Sign in with Apple link,
then calls `DELETE /users/me`.
