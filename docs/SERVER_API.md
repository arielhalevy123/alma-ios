# Server API used by the app

Base URL: `https://gen-seller-production.up.railway.app` (set in `Info.plist` as
`AlmaAPIBaseURL`, with the same address as a fallback in `AlmaAPI.swift`).

All requests and responses are JSON, except `POST /design`, which uploads the photo as
`multipart/form-data`. Requests marked "yes" under Auth send
`Authorization: Bearer <access token>`.

## Endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/auth/apple/callback` | no | Exchange a Sign in with Apple identity token for Alma tokens. |
| POST | `/auth/google/callback` | no | Exchange a Google authorisation code (with the PKCE verifier) for Alma tokens. |
| POST | `/auth/refresh` | no | Exchange a refresh token for a new access token. |
| GET | `/users/me/usage` | yes | Designs used and left. |
| DELETE | `/users/me` | yes | Delete the account (for Apple accounts, the app first re-confirms with Apple so the link can be revoked). |
| GET | `/catalog/retailers` | no | The stores products can come from, with their logos. |
| POST | `/design` | yes | Start a redesign: photo plus optional hints. Returns the finished design. |
| GET | `/design/{id}` | yes | Read a design by id (used only if a design is still in progress). |
| POST | `/rooms` | yes | Save a design to "My designs" (creates a room). |
| POST | `/rooms/{id}/designs` | yes | Attach the design to that saved room. |
| GET | `/rooms/designs/latest` | yes | List the user's saved designs. |
| PATCH | `/rooms/{id}` | yes | Rename a saved design. |
| DELETE | `/rooms/{id}` | yes | Delete a saved design. |
| GET | `/billing/plans` | no | The plans and products on sale, with their App Store product ids. |
| GET | `/billing/entitlement` | yes | The user's current plan and balance of designs. |
| POST | `/billing/apple/sync` | yes | Send an App Store signed transaction (JWS) to be verified and credited. |

## `POST /design` request

Multipart form fields (all but `image` are optional hints):

| Field | Type | Meaning |
|---|---|---|
| `image` | JPEG file | The room photo. |
| `marked_image` | JPEG file | The same photo with the user's strokes drawn on it ("change this"). |
| `room_hint` | text | Room type the user picked (living room, bedroom...). |
| `palette_hint` | text | Colour palette the user picked. |
| `prompt` | text | Free text from the user ("make it brighter"). |
| `retailers` | text | Stores to take products from; empty means all. |

## Errors the app handles

| Status | Meaning | What the app does |
|---|---|---|
| 401 | Access token expired | Calls `/auth/refresh` once and repeats the request. If that fails, signs the user out. |
| 402 | No designs left | Shows the paywall. |
| other 4xx/5xx | Server error | Shows the server's message, or a general error. |

## Tokens

- **Access token:** a JWT valid for 15 minutes, sent on every authenticated request.
- **Refresh token:** valid for 30 days, used only to get a new access token. Each
  refresh returns a new refresh token; if an old one is reused, the server treats it as
  theft and revokes all of that user's sessions.
- Both are stored in the iOS Keychain (`Keychain.swift`), scoped to this app and
  readable after the first unlock following a reboot.
