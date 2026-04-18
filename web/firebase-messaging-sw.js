// FCM background handler for web push. Replace the config below with your Firebase web app config
// (Firebase Console → Project settings → Your apps → Web app), or use the same values as FIREBASE_WEB_* dart-defines.
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

const firebaseConfig = {
  apiKey: 'YOUR_WEB_API_KEY',
  projectId: 'YOUR_PROJECT_ID',
  messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
  appId: 'YOUR_WEB_APP_ID',
};

firebase.initializeApp(firebaseConfig);
const messaging = firebase.messaging();

messaging.onBackgroundMessage(function (payload) {
  const title = payload.notification?.title || 'Parking Trade';
  const options = { body: payload.notification?.body || '' };
  self.registration.showNotification(title, options);
});
