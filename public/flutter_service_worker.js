'use strict';

const CACHE_NAME = 'stonex-erp-pwa-v3';
const CORE_ASSETS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/flutter.js',
  '/flutter_bootstrap.js',
  '/main.dart.js',
  '/version.json',
  '/favicon.png',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
  '/assets/FontManifest.json',
  '/assets/AssetManifest.bin.json',
  '/canvaskit/canvaskit.js',
  '/canvaskit/canvaskit.wasm'
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(CORE_ASSETS).catch((err) => {
        console.warn('[PWA ServiceWorker] Pre-cache warning:', err);
      });
    })
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((name) => {
          if (name !== CACHE_NAME) {
            return caches.delete(name);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // API va backend so'rovlariga xalaqit bermaslik (to'g'ridan-to'g'ri tarmoqqa ketadi)
  if (
    url.hostname.includes('onrender.com') ||
    url.pathname.startsWith('/api') ||
    url.pathname.startsWith('/auth') ||
    url.pathname.startsWith('/sales') ||
    url.pathname.startsWith('/products') ||
    url.pathname.startsWith('/stock') ||
    url.pathname.startsWith('/customers') ||
    url.pathname.startsWith('/finance') ||
    url.pathname.startsWith('/ping')
  ) {
    return;
  }

  // Boshqa barcha statik resurslar uchun (Cache-First / Stale-While-Revalidate)
  event.respondWith(
    caches.match(req).then((cachedResp) => {
      const fetchPromise = fetch(req)
        .then((networkResp) => {
          if (networkResp && networkResp.status === 200 && req.method === 'GET') {
            const respClone = networkResp.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(req, respClone));
          }
          return networkResp;
        })
        .catch(() => {
          // Tarmoq uzilganda agar navigatsiya bo'lsa index.html qaytarish
          if (req.mode === 'navigate') {
            return caches.match('/index.html') || caches.match('/');
          }
          return cachedResp;
        });

      return cachedResp || fetchPromise;
    })
  );
});
