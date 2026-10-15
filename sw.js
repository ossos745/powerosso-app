// Powerosso App: permite instalarla desde Chrome. Siempre busca la versión nueva en internet;
// si no hay conexión, abre la última copia guardada. Los datos (Supabase) nunca se guardan aquí.
const CACHE = 'powerosso-v1';
self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(['./', 'config.js', 'manifest.json', 'assets/icon-192.png'])).catch(() => {}));
});
self.addEventListener('activate', e => e.waitUntil(
  caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener('fetch', e => {
  const r = e.request, u = new URL(r.url);
  if (r.method !== 'GET' || u.origin !== location.origin) return;
  e.respondWith(fetch(r).then(res => {
    if (res.ok) { const cp = res.clone(); caches.open(CACHE).then(c => c.put(u.origin + u.pathname, cp)); }
    return res;
  }).catch(() => caches.match(u.origin + u.pathname).then(m => m || caches.match('./'))));
});
