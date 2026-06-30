const VERSION = '20260630-weight-swap';
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

// Fetch: network first, fall back to cache
self.addEventListener('fetch', e => {
  e.respondWith(
    fetch(e.request)
      .then(r => {
        const clone = r.clone();
        caches.open(CACHE).then(c => c.put(e.request, clone));
        return r;
      })
      .catch(() => caches.match(e.request))
  );
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
