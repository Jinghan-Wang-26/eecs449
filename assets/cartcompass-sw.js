/* CartCompass public-only offline support.
 * NEVER cache accounts, walkers, tokens, shopping responses, or submitted data.
 * Keep this worker at the origin root so the installed app's / is in scope.
 */
const CACHE = "cartcompass-public-v1";
const OFFLINE = "/static/mobile/offline.html";
const PUBLIC_FILES = [
  OFFLINE,
  "/static/mobile/icon-192.png",
  "/static/mobile/icon-512.png",
  "/static/mobile/apple-touch-icon.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(PUBLIC_FILES)));
  // Let an existing client finish before activating a changed worker.
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith("cartcompass-public-") && name !== CACHE) {
        await caches.delete(name);
      }
    }
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);
  // Everything except these explicitly public resources uses the network only.
  // In particular, no /user, /walker, /function, or third-party request is handled.
  if (request.method !== "GET" || url.origin !== self.location.origin ||
      request.headers.has("Authorization")) return;
  if (PUBLIC_FILES.includes(url.pathname) && !url.search) {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE);
      return (await cache.match(url.pathname)) || fetch(request);
    })());
  } else if (request.mode === "navigate" && url.pathname === "/") {
    event.respondWith(fetch(request).catch(async () => {
      const cache = await caches.open(CACHE);
      return (await cache.match(OFFLINE)) || new Response(
        "You are offline. Reconnect to open CartCompass.",
        { status: 503, headers: { "Content-Type": "text/plain; charset=utf-8" } }
      );
    }));
  }
});
