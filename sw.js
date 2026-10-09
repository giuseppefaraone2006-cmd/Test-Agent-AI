const CACHE_NAME = 'lega-sanninica-shell-v1';
const APP_BASE = new URL('./', self.location.href);
const APP_FILES = [
  '',
  'index.html',
  'manifest.webmanifest',
  'images/pwa-192.png',
  'images/pwa-512.png',
  'images/apple-touch-icon.png',
  'images/LOGO LEGA PANTALONCINI.jpg'
];
const APP_URLS = APP_FILES.map(path => new URL(path || './', APP_BASE).href);
const APP_STATIC_URLS = new Set(APP_URLS);
const APP_INDEX_URL = new URL('index.html', APP_BASE);

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(APP_URLS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys
        .filter(key => key.startsWith('lega-sanninica-shell-') && key !== CACHE_NAME)
        .map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;

  if (request.mode === 'navigate' &&
      (url.pathname === APP_BASE.pathname || url.pathname === APP_INDEX_URL.pathname)) {
    event.respondWith(
      fetch(request).catch(async () => (await caches.match(APP_INDEX_URL)) || Response.error())
    );
    return;
  }

  if (APP_STATIC_URLS.has(request.url)) {
    event.respondWith(
      caches.match(request).then(response => response || fetch(request))
    );
  }
});
