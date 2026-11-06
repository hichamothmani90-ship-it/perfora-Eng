/* Hors ligne : l'application est mise en cache et s'ouvre sans réseau.
   Changer VERSION à chaque livraison pour forcer la mise à jour. */
const VERSION = 'gmao-terrain-v3';
const FILES = ['./', './index.html', './css/app.css', './js/store.js', './js/calculs.js', './js/qr.js', './js/app.js', './manifest.webmanifest', './icon.svg'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(FILES)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
// Cache d'abord (instantané, marche hors ligne), puis mise à jour en arrière-plan.
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  e.respondWith(caches.open(VERSION).then(async c => {
    const hit = await c.match(req, { ignoreSearch: true });
    const net = fetch(req).then(r => { if (r.ok) c.put(req, r.clone()); return r; }).catch(() => hit);
    return hit || net;
  }));
});
