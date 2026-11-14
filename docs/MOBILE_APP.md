# CartCompass mobile app (PWA)

CartCompass can be installed from a browser as a Progressive Web App. It uses
our existing Jac client, account login and per-user shopping workspace. There
is no separate mobile backend, app-store account or additional API key.

## Install on a phone

First deploy this branch, including the account changes it builds on, to your
HTTPS server. The currently published site will not gain these features until
that deployment completes. Open its HTTPS URL directly in a browser:

- **Android / Chrome:** tap **Install app** in CartCompass and accept the
  browser prompt. If the prompt is unavailable, use the browser menu's
  **Install app** or **Add to Home screen** option.
- **iPhone / iPad:** open in Safari, tap **Share → Add to Home Screen**, enable
  **Open as Web App** if shown, then tap **Add**. The in-app button explains
  these steps; Safari does not supply Chromium's install prompt.
- **Desktop / Chrome or Edge:** use **Install app** or the browser's address-bar
  installation icon when available.

Launch CartCompass from its home-screen icon and sign in. The same account
loads the same server-stored lists and plans on another device. The installed
app may need a fresh login even if a browser is already signed in. On phones,
use the bottom **Plan / Assistant** navigation to switch views. **+ New trip**
opens a confirmation explaining which trip data is reset. Select **Start new
trip** to continue or **Keep this trip** to cancel.
The interface supports safe areas, 44px buttons and 16px form inputs.

## Offline behavior and updates

Shopping requires a connection. If the browser reports that it is offline,
a visible banner warns that displayed information may be stale and disables
workspace inputs and buttons. Existing in-memory content can remain visible
until the page closes. No changes are queued and no offline writes are replayed.
An interrupted request may already have reached the server: reconnect and
inspect your workspace before retrying an operation.

After one connected visit prepares the service worker, reopening the app
without a connection shows a public **You are offline** page. **Try again**
returns to the normal login/session check when connected. This is not an
offline copy of a shopping plan. Browser storage eviction can remove this
fallback; a subsequent connected visit prepares it again.

`assets/cartcompass-sw.js` caches only the public offline page and three icons.
It never stores HTML from a user's workspace, accounts, bearer tokens, chat,
API responses, prices or submitted forms. Account tokens continue to use the
existing Jac browser storage; the service worker does not read them. Logout
still revokes the server session. Personal data stays behind authenticated
Jac walkers.

The regular Jac web build is intentional. The pinned Jac PWA target generates
a generic worker with different caching and scope behavior; do not replace
our worker with it or run `jac build --client pwa` for this application.
`server/mobile_assets.jac` also avoids the pinned runtime's static-hook
fall-through (a successful response followed by a second HTTP error). It
serves only files inside the project's public `assets/` directory; generated
client JavaScript and CSS retain their dedicated Jac handlers.
Change the `cartcompass-public-v1` cache version when changing cached public
assets. A new worker activates after existing app windows close; it does not
force-refresh an active shopping conversation. Client code itself loads from
the network, so a normal online reload gets the latest deployed UI.

## Test locally

```bash
source .venv/bin/activate
jac build main.jac
jac start main.jac --port 8000
```

Open **http://localhost:8000** on the same computer. Chromium treats localhost
as a secure context, so the manifest and worker can be tested there. A phone's
`localhost` points to the phone, not the computer. Plain
`http://<computer-LAN-IP>:8000` is insufficient for PWA installation and some
browser features. Use the deployed HTTPS URL for a phone test. On Android,
an optional USB developer setup with `adb reverse tcp:8000 tcp:8000` lets
Chrome on that phone reach the computer at `http://localhost:8000`.

In DevTools, use **Application → Manifest / Service Workers / Cache Storage**
to inspect installation and confirm the worker controls `/`. Disable network
access to check the warning and reload to see the public offline page; restore
network and select **Try again**. Sign out and use another account to confirm
that the previous user's workspace disappears.

Automated Chromium verification (isolated temporary accounts; no external
service credentials or real user data):

```bash
python -m pip install -r requirements-browser.txt
python -m playwright install chromium
python scripts/verify_mobile.py
```

Set `CHROMIUM_EXECUTABLE_PATH` only when using an existing Chromium binary.
The check covers manifest/icons/installation criteria, install-help UI,
mobile and desktop widths, login and account switching, visible item entry,
missing-detail shortcuts, preference saving, trip-reset confirmation, shopping navigation,
service-worker scope, cache privacy, disabled offline actions, offline launch,
reconnection and logout. It uses synthetic browser install events to test the
UI; actual Android/iPhone installation still requires a physical-device test.

## Scope

This is an installable PWA, not an APK or an App Store release. It does not
provide push notifications, background GPS, offline shopping edits, automatic
background ordering or native payment features. Prices and transit retain
the same coverage and freshness limits as the website.

Browser references: [PWA installation requirements](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable),
[Apple home-screen installation](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/ios),
[service worker registration and secure contexts](https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerContainer/register).
