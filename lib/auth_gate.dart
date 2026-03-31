import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_screen.dart';
import 'username_screen.dart';
import 'home_screen.dart';
import 'services/notification_service.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final NotificationService _notificationService = NotificationService();
  bool _notificationsInitialized = false;
  String? _initializedForUserId;

  Future<void> _initNotificationsForUser(String uid) async {
    if (_notificationsInitialized && _initializedForUserId == uid) return;

    _notificationsInitialized = true;
    _initializedForUserId = uid;

    try {
      await _notificationService.initNotifications();
    } catch (e) {
      debugPrint('Notification init error: $e');
    }
  }

  void _resetNotificationInit() {
    _notificationsInitialized = false;
    _initializedForUserId = null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (authSnapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Auth error')),
          );
        }

        if (!authSnapshot.hasData) {
          _resetNotificationInit();
          return const LoginScreen();
        }

        final user = authSnapshot.data!;

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (userSnapshot.hasError) {
              return const Scaffold(
                body: Center(child: Text('User data error')),
              );
            }

            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
              return const UsernameScreen();
            }

            final data = userSnapshot.data!.data();

            if (data == null || data['username'] == null) {
              return const UsernameScreen();
            }

            _initNotificationsForUser(user.uid);

            return HomeScreen();
          },
        );
      },
    );
  }
}