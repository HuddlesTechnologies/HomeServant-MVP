// Web Push service worker (see backend PushService). Registered by the app
// with scope ./push/ so it never interferes with Flutter's own files; its
// only jobs are showing a notification when a push arrives and focusing
// (or opening) the app when one is clicked.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { title: 'HomeServant', body: event.data ? event.data.text() : '' };
  }
  event.waitUntil(
    (async () => {
      // The app is open and in view: its own in-app banner already shows it.
      const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      if (windows.some((w) => w.visibilityState === 'visible')) return;
      await self.registration.showNotification(data.title || 'HomeServant', {
        body: data.body || '',
        // Same tag as the in-tab pop-up, so the browser replaces, not stacks.
        tag: data.tag,
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        data: { url: data.url || '/' },
      });
    })(),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL((event.notification.data && event.notification.data.url) || '/', self.location.origin).href;
  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const w of windows) {
        if ('focus' in w) return w.focus();
      }
      return self.clients.openWindow(url);
    })(),
  );
});
