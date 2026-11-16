# User accounts and workspace isolation

Run `jac start main.jac --port 8000` in the project environment and open
http://localhost:8000. The public page offers **Sign in** and **Create an account**.
Registration requires a username (3–64 characters) and a password (12–128
characters). Usernames are case-insensitive. No additional API key or email
service is required for accounts.

After registration, the app signs in and opens an empty workspace. The header
shows the username and **Sign out**. Refreshing the page validates the session
with the server before mounting shopping components. Signing out revokes the
current session on the server and removes its browser token. Sessions expire
12 hours after login. Separate browsers/devices can have separate sessions;
a password change revokes all sessions for that account.

## Data boundary

Jac assigns each account its own root. Its address, preferences, interests,
plans, chat, spending ledger, notification settings and delivery quotes live
below that root. All shopping walkers require authentication. Operations also
check that their target root matches the authenticated root; a client cannot
select another workspace by sending a user ID or foreign graph root.

The old `__guest__` graph is retained but is inaccessible through account APIs
and excluded from background reminders. It is not assigned to the first user
who registers. Existing named Jac accounts retain their roots and can sign in;
legacy password hashes upgrade after successful authentication. Old permanent
Jac tokens are no longer accepted.

Public provider responses may be cached across accounts (for example a
retailer price for a particular store/product). Personal shopping workspace
responses are not shared between users. Browser token changes reload other
tabs, and account changes clear Jac client caches and remount the workspace.

## Implementation and limits

- `server/accounts.jac` adapts the pinned Jac 0.16.7 user manager using Python's
  standard cryptographic and SQLite libraries from Jac. Passwords use scrypt
  with a fresh random salt. Bearer tokens are random, stored as hashes in a
  separate session table, and checked for expiry on every authenticated call.
- Login failures are limited to eight per username per 15-minute window. This
  is a basic local limit; registration and overall request volume still need
  deployment-level controls for a larger public service.
- The Jac client uses `jac_token` in local storage. Use HTTPS outside localhost;
  browser script access to tokens means preventing XSS remains important.
- Caddy forwards `Authorization` to Jac and sends `Cache-Control: no-store`.
  It no longer strips the bearer token. No shared website password is needed.
- Accounts do not provide email verification, password recovery, social login,
  account deletion, or administrative roles. `PUT /user/password` supports an
  authenticated change with the current password; a settings UI is future work.
- This is one application instance with isolated user data, not a distributed
  deployment. Synchronous provider calls can still delay concurrent requests.
- Keep both `.jac/data/main.db` and `.jac/data/cartcompass.db` on persistent
  storage. On Render, the disk mounts at `/var/data` with
  `JAC_DATA_PATH=/var/data`. Temporary filesystems lose accounts as well as plans.

## Verify locally

```bash
source .venv/bin/activate
python -m unittest discover -s tests -p 'test_accounts.py' -v
python scripts/verify_accounts.py
jac build main.jac
jac start main.jac --port 8000
```

The HTTP script uses temporary databases and synthetic accounts with all
external credentials disabled. It verifies anonymous/forged-token rejection,
registration validation, independent roots, list/chat/plan/budget isolation,
foreign-root and foreign-object attacks, logout revocation, password changes,
expiry, and persistence across a real server restart.

For a browser check, use a normal window for account A and a private window
for account B. Add milk and a budget entry for A, then rice for B. Confirm that
each sees only its own data. Sign A out and sign B into that window: A's chat
and list should disappear. Restart the server and sign back into A to verify
persistence. Two normal tabs share browser storage; use a private window or
separate browser profile to keep two accounts signed in simultaneously.
