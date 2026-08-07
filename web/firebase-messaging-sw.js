/* Firebase Messaging service worker (no secrets committed). */
importScripts('https://www.gstatic.com/firebasejs/9.6.10/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.6.10/firebase-messaging-compat.js');

try {
  importScripts('/firebase-messaging-config.js');
} catch (_) {
  // Missing local config file: background messaging remains disabled.
}

const firebaseConfig =
  (self.__FIREBASE_MESSAGING_CONFIG__ && typeof self.__FIREBASE_MESSAGING_CONFIG__ === 'object')
    ? self.__FIREBASE_MESSAGING_CONFIG__
    : null;

if (firebaseConfig && firebaseConfig.apiKey) {
  firebase.initializeApp(firebaseConfig);
  const messaging = firebase.messaging();

  messaging.onBackgroundMessage((payload) => {
    const title = payload?.notification?.title || 'Notification';
    const options = {
      body: payload?.notification?.body || '',
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      tag: payload?.notification?.tag || 'adfoot-fcm',
      data: payload?.data || {},
      color: '#2ED573',
    };

    self.registration.showNotification(title, options);
  });
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      const targetUrl =
        event.notification?.data && event.notification.data.url
          ? event.notification.data.url
          : '/';

      for (const client of clientList) {
        if (client.url === targetUrl && 'focus' in client) {
          return client.focus();
        }
      }

      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }

      return undefined;
    }),
  );
});
