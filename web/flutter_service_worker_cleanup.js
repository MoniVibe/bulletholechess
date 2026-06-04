const FLUTTER_CACHE_PREFIXES = [
  'flutter-app-cache',
  'flutter-temp-cache',
  'flutter-app-manifest',
];

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const cacheKeys = await caches.keys();
    await Promise.all(
      cacheKeys
        .filter((key) => FLUTTER_CACHE_PREFIXES.some((prefix) => key.startsWith(prefix)))
        .map((key) => caches.delete(key)),
    );

    await self.clients.claim();
    const clients = await self.clients.matchAll({
      includeUncontrolled: true,
      type: 'window',
    });
    await self.registration.unregister();

    for (const client of clients) {
      if ('navigate' in client) {
        await client.navigate(client.url);
      }
    }
  })());
});
