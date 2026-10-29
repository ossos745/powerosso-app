// Powerosso App: permite instalarla desde Chrome. Siempre busca la versión nueva en internet;
// si no hay conexión, abre la última copia guardada. Los datos (Supabase) nunca se guardan aquí.
const CACHE = 'powerosso-v3';
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
// tocar un aviso abre la app
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const obs = e.notification.data && e.notification.data.obs;  // aviso de observación: abre la pestaña Observaciones
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(cs => {
    for (const c of cs) if ('focus' in c) { if (obs) c.postMessage({ obs: true }); return c.focus(); }
    return self.clients.openWindow(obs ? './?ver=obs' : './');
  }));
});
// aviso push (observación nueva de un alumno): se muestra aunque la app esté cerrada
self.addEventListener('push', e => {
  let d = {}; try { d = e.data ? e.data.json() : {}; } catch (x) { d = { body: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.title || 'Powerosso', {
    body: d.body || '', tag: d.tag, icon: 'assets/icon-192.png', badge: 'assets/icon-192.png', data: { url: d.url || './', obs: true } }));
});
