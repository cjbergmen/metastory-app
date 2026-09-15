const VERSION = '20260915-fdnlens';
const CACHE = 'cjf-v' + VERSION;

// Install: skip waiting so new SW activates immediately
self.addEventListener('install', () => self.skipWaiting());

// Activate: delete old caches, claim all clients
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
      .then(() => {
        // Tell all open tabs/windows to reload for fresh content
        return self.clients.matchAll({type: 'window'});
      })
      .then(clients => clients.forEach(c => c.postMessage({type: 'RELOAD'})))
  );
});

// Fetch: network first, fall back to cache.
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  // Audio streams (Safe Inside album) go straight to the network — the browser
  // handles range requests natively, and partial (206) responses can't be cached.
  if (req.url.includes('/audio/')) return;

  let url;
  try { url = new URL(req.url); } catch (err) { return; }

  // Never hand respondWith an undefined — that surfaces to the page as a hard
  // network error, which on a navigation means a blank screen.
  const fallback = async () => {
    const cached = await caches.match(req);
    if (cached) return cached;
    try { return await fetch(req); }
    catch (err) { return new Response('', { status: 504, statusText: 'Offline' }); }
  };

  const store = async (response) => {
    try { const c = await caches.open(CACHE); await c.put(req, response.clone()); }
    catch (err) {}
  };

  // Third-party code (the Firebase SDK, fonts) is fetched exactly as asked for.
  // Rewriting those requests is what broke the app: a cross-origin script asked
  // for as same-origin fails outright.
  if (url.origin !== self.location.origin) {
    e.respondWith((async () => {
      try { const r = await fetch(req); store(r); return r; }
      catch (err) { return fallback(); }
    })());
    return;
  }

  // Our own page and code always revalidate. "Network first" still went through
  // the HTTP cache, and the host serves the page with a ten-minute max-age, so
  // for ten minutes after a deploy the fresh fetch quietly returned the old
  // build. Images and fonts keep their normal caching.
  const isCode = req.mode === 'navigate' ||
                 url.pathname === '/' ||
                 /\.(html|js|json|css)$/.test(url.pathname);

  e.respondWith((async () => {
    try {
      const r = await fetch(isCode ? new Request(url.href, { cache: 'reload' }) : req);
      store(r);
      return r;
    } catch (err) {
      return fallback();
    }
  })());
});

// ── TIMER NOTIFICATIONS ───────────────────────────────────────────────────────
// The page sends SCHEDULE_TIMER_NOTIF when a timer starts so the SW can fire
// a system notification even when the app is backgrounded.
// e.waitUntil keeps the SW alive until the notification fires.
let _timerNotifId = null;

self.addEventListener('message', e => {
  if(!e.data) return;

  if(e.data.type === 'SCHEDULE_TIMER_NOTIF') {
    // Cancel any previous pending notification
    if(_timerNotifId !== null) { clearTimeout(_timerNotifId); _timerNotifId = null; }
    const delayMs = Math.max(0, e.data.delayMs || 0);
    e.waitUntil(new Promise(resolve => {
      _timerNotifId = setTimeout(async () => {
        _timerNotifId = null;
        try {
          await self.registration.showNotification(e.data.title || '⏱ Rest Over', {
            body: e.data.body || "Time to lift again!",
            icon: '/icon-192.png',
            badge: '/icon-192.png',
            tag: 'cjf-timer',
            renotify: true,
            vibrate: [300, 150, 300, 150, 300],
            silent: false
          });
        } catch(err) {}
        resolve();
      }, delayMs);
    }));
  }

  if(e.data.type === 'CANCEL_TIMER_NOTIF') {
    if(_timerNotifId !== null) { clearTimeout(_timerNotifId); _timerNotifId = null; }
    // Also dismiss any visible timer notification
    self.registration.getNotifications({tag: 'cjf-timer'})
      .then(notifs => notifs.forEach(n => n.close()))
      .catch(()=>{});
  }
});

// Tapping the notification opens/focuses the app
self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(
    self.clients.matchAll({type:'window', includeUncontrolled:true}).then(clients => {
      for(const c of clients) { if('focus' in c) return c.focus(); }
      if(self.clients.openWindow) return self.clients.openWindow('/');
    })
  );
});
