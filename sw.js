/* Hors ligne : l'application est mise en cache et s'ouvre sans réseau.
   Changer VERSION à chaque livraison pour forcer la mise à jour. */
const VERSION = 'gmao-terrain-v19';
const FILES = ['./', './index.html', './css/app.css', './js/store.js', './js/sync.js', './js/calculs.js', './js/qr.js', './js/app.js', './js/vues/magasin.js', './manifest.webmanifest', './icon.svg'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(FILES.map(f => new Request(f, { cache: 'reload' })))).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
// Cache d'abord, version par version : un fichier n'est jamais mis à jour isolément
// (sinon on mélangerait index.html d'une version et app.js d'une autre).
// Une nouvelle livraison = nouvelle VERSION = nouveau cache complet, installé d'un bloc.
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  e.respondWith(caches.open(VERSION).then(async c => (await c.match(req, { ignoreSearch: true })) || fetch(req)));
});
