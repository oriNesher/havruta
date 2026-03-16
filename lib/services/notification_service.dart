import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> initNotifications() async {
    final user = _auth.currentUser;
    if (user == null) return;

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

    // קבלת הטוקן הנוכחי
    final token = await _messaging.getToken();
    if (token != null) {
      await _saveTokenToUser(user.uid, token);
    }

    // האזנה לרענון טוקן
    _messaging.onTokenRefresh.listen((newToken) async {
      await _saveTokenToUser(user.uid, newToken);
    });
  }

  Future<void> _saveTokenToUser(String uid, String token) async {
    final userRef = _firestore.collection('users').doc(uid);

    await userRef.set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }
}