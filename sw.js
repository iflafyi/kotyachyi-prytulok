/* Котячий притулок: офлайн-кеш. Гра завжди бере свіжу версію з мережі, а без інтернету — з кешу. */
const CACHE = 'kp-202610251825';
const CORE = ['./', 'art/sis-lime.png', 'art/sis-siam.png', 'index.html', 'config.js', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png'];
const CDN = /^(https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com|fonts\.googleapis\.com|fonts\.gstatic\.com))\//;
self.addEventListener('install', e => { self.skipWaiting(); e.waitUntil(caches.open(CACHE).then(c => c.addAll(CORE)).catch(() => {})); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k.startsWith('kp-') && k !== CACHE && k !== 'kp-cdn').map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const r = e.request; if (r.method !== 'GET') return;
  const u = new URL(r.url);
  if (CDN.test(r.url)){
    e.respondWith(caches.open('kp-cdn').then(c => c.match(r).then(hit => hit || fetch(r).then(res => { if (res.ok || res.type === 'opaque') c.put(r, res.clone()); return res; }))));
    return;
  }
  if (u.origin !== location.origin || u.pathname.endsWith('version.json') || u.pathname.endsWith('sw.js')) return;
  e.respondWith((async () => {
    const c = await caches.open(CACHE);
    try {
      const res = await fetch(r, {cache: 'no-cache'});
      if (res.ok) c.put(r.mode === 'navigate' ? 'index.html' : r, res.clone());
      return res;
    } catch(err){
      return (await c.match(r.mode === 'navigate' ? 'index.html' : r)) || (await c.match(r, {ignoreSearch: true})) || Response.error();
    }
  })());
});
