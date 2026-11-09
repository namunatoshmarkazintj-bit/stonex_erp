'use strict';

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      try {
        const cacheKeys = await caches.keys();
        await Promise.all(cacheKeys.map(k => caches.delete(k)));
        await self.registration.unregister();
      } catch (e) {
        console.warn('Failed to unregister or clear cache:', e);
      }

      try {
        const clients = await self.clients.matchAll({
          type: 'window',
        });
        clients.forEach((client) => {
          if (client.url && 'navigate' in client) {
            client.navigate(client.url);
          }
        });
      } catch (e) {
        console.warn('Failed to navigate clients:', e);
      }
    })()
  );
});
