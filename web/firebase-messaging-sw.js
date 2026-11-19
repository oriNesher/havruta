// Firebase Cloud Messaging service worker for web push. getToken() in the
// web app registers this file (it must live at the site root); it shows
// notifications that arrive while no Havruta tab is focused. Inert until a
// VAPID key is set in lib/services/web_push_config.dart — without one the
// app never asks for permission or calls getToken().
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

// The web app's public Firebase config (same values as the web section of
// lib/firebase_options.dart).
firebase.initializeApp({
  apiKey: 'AIzaSyDkt9z8JES3Pvcs18xBAES5_Dy0Z3xGWxg',
  appId: '1:943688238219:web:64ffe33b31f0850043c08e',
  messagingSenderId: '943688238219',
  projectId: 'havruta-app',
  authDomain: 'havruta-app.firebaseapp.com',
  storageBucket: 'havruta-app.firebasestorage.app',
});

// Messages carrying a `notification` block (all of Havruta's) are shown by
// the SDK itself; nothing else to handle here.
firebase.messaging();
