/* Import des SDK compat pour le Service Worker Firebase Messaging */
importScripts('https://www.gstatic.com/firebasejs/9.6.10/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.6.10/firebase-messaging-compat.js');

/* Configuration Firebase du projet */
firebase.initializeApp({
  apiKey: "BLngrlSTZrTe-mexPQOdiYul_qFP1bRZnrv7UCHwVA9vXkuYUJ1oJ3tUnD5B5QDyk6d1eSVRFG18ECIEBAazUho",
  authDomain: "show-talent-5987d.firebaseapp.com",
  projectId: "show-talent-5987d",
  storageBucket: "show-talent-5987d.appspot.com",
  messagingSenderId: "43422248234",
  appId: "1:43422248234:web:90e6e10558e53ab4f8c253"
});

/* Initialisation du service Firebase Messaging */
const messaging = firebase.messaging();

/* Gestion des notifications push reçues en arrière-plan */
messaging.onBackgroundMessage((payload) => {
  // Extraction sécurisée des données de la notification
  const title = payload?.notification?.title || 'Notification';
  const options = {
    body: payload?.notification?.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    // Ajout optionnel d’un tag pour éviter les doublons
    tag: payload?.notification?.tag || 'adfoot-fcm',
    // Ajout optionnel de data pour une action personnalisée sur click
    data: payload?.data || {},
    // Ajout d’une couleur (optionnel, certains navigateurs l’ignorent)
    color: "#2ED573"
  };

  // Affiche la notification dans le navigateur
  self.registration.showNotification(title, options);
});

/* Gestion du click sur la notification */
self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  // Ouvre l’URL principale de l’app ou utilise event.notification.data
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      // Ouvre/focus l’onglet principal si déjà ouvert
      for (const client of clientList) {
        // Si l’utilisateur a cliqué sur une notification avec une url spécifique (data.url), ouvre cette url
        const targetUrl = event.notification.data && event.notification.data.url ? event.notification.data.url : '/';
        if (client.url === targetUrl && 'focus' in client) {
          return client.focus();
        }
      }
      // Sinon ouvre un nouvel onglet
      const targetUrl = event.notification.data && event.notification.data.url ? event.notification.data.url : '/';
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});

/* Sécurité : Ne jamais demander la permission ou le token ici ! */
/* Ce SW ne fait que gérer les notifications en arrière-plan */
