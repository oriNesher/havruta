import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

import 'web_push_config.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> initNotifications() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Web never asks here, at sign-in — the worst-converting moment, and a
    // reliable way to get permanently blocked. It only re-registers a token
    // the user already granted; the ask itself is enableWebPush(), offered
    // on Home. Off entirely until a VAPID key is configured.
    if (kIsWeb) {
      if (!webPushConfigured) return;
      final settings = await _messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        await _registerToken(user.uid);
      }
      return;
    }

    // בקשת הרשאה
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // אם המשתמש לא אישר, לא ממשיכים
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    await _registerToken(user.uid);
  }

  /// Whether to offer turning on browser notifications: web, configured,
  /// and the browser hasn't been asked yet (granted or blocked means
  /// there's nothing to offer).
  Future<bool> shouldOfferWebPush() async {
    if (!kIsWeb || !webPushConfigured) return false;
    try {
      final settings = await _messaging.getNotificationSettings();
      return settings.authorizationStatus ==
          AuthorizationStatus.notDetermined;
    } catch (e) {
      debugPrint('Web push status unavailable: $e');
      return false;
    }
  }

  /// Asks the browser for notification permission and, if granted,
  /// registers this browser's push token. Returns whether it's now on.
  Future<bool> enableWebPush() async {
    final user = _auth.currentUser;
    if (!kIsWeb || !webPushConfigured || user == null) return false;
    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      return false;
    }
    await _registerToken(user.uid);
    return true;
  }

  Future<void> _registerToken(String uid) async {
    // קבלת הטוקן הנוכחי
    final token = await _messaging.getToken(
      vapidKey: kIsWeb ? kWebPushVapidKey : null,
    );
    if (token != null) {
      await _saveTokenToUser(uid, token);
    }

    // האזנה לרענון טוקן
    _messaging.onTokenRefresh.listen((newToken) async {
      await _saveTokenToUser(uid, newToken);
    });
  }

  Future<void> _saveTokenToUser(String uid, String token) async {
    final userRef = _firestore.collection('users').doc(uid);

    await userRef.set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }
}
