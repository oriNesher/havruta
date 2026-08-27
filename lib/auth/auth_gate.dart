import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_screen.dart';
import 'username_screen.dart';
import '../celebrations/celebration_gate.dart';
import '../home/home_screen.dart';
import '../services/notification_service.dart';
import '../services/pending_invite_store.dart';
import '../competitions/invite_redeem_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final NotificationService _notificationService = NotificationService();
  final PendingInviteStore _pendingInviteStore = PendingInviteStore();
  bool _notificationsInitialized = false;
  String? _initializedForUserId;
  bool _pendingInviteChecked = false;
  String? _pendingInviteLinkId;

  late final StreamSubscription<User?> _authSubscription;

  // Routing state — only changed when the user *actually* changes (uid differs).
  // Re-emissions of the same user (token refresh, back-nav focus events) do not
  // call setState, so HomeScreen is never unmounted unnecessarily.
  bool _loading = true;
  User? _user;
  Map<String, dynamic>? _userDocData;
  String? _userDocLoadedForUid;

  @override
  void initState() {
    super.initState();
    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  void _onAuthChanged(User? user) {
    if (user?.uid == _user?.uid) {
      // Same user — could be a token refresh or a spurious re-emission from
      // Firebase Auth when the app regains focus after back navigation.
      // Just update the User object in place; do NOT call setState so the
      // widget tree (including HomeScreen) is never rebuilt.
      _user = user;
      if (_loading) setState(() => _loading = false);
      return;
    }

    // User actually changed (sign-in, sign-out, or account switch).
    setState(() {
      _user = user;
      if (user == null) {
        _loading = false;
        _userDocData = null;
        _userDocLoadedForUid = null;
        _resetNotificationInit();
        _pendingInviteChecked = false;
        _pendingInviteLinkId = null;
      } else {
        _loading = true; // show spinner while fetching user doc
      }
    });

    if (user != null) _fetchUserDoc(user.uid);
  }

  Future<void> _fetchUserDoc(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      // Guard: user may have changed or widget may have been disposed.
      if (!mounted || _user?.uid != uid) return;
      setState(() {
        _userDocData = doc.data();
        _userDocLoadedForUid = uid;
        _loading = false;
      });
    } catch (e) {
      debugPrint('User doc fetch error: $e');
      if (mounted && _user?.uid == uid) setState(() => _loading = false);
    }
  }

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

  Future<void> _checkPendingInvite(String uid) async {
    if (_pendingInviteChecked) return;
    _pendingInviteChecked = true;
    try {
      final linkId = await _pendingInviteStore.getPendingInviteToken();
      if (linkId == null) return;
      // Clear on entry, not only on successful redemption — otherwise a user
      // who backs out of the redeem screen would see it again every launch.
      await _pendingInviteStore.clearPendingInviteToken();
      if (mounted && _user?.uid == uid) {
        setState(() => _pendingInviteLinkId = linkId);
      }
    } catch (e) {
      debugPrint('Pending invite check error: $e');
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_user == null) {
      return const LoginScreen();
    }

    // Covers the narrow gap between sign-in and user doc arriving.
    if (_userDocLoadedForUid != _user!.uid) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final data = _userDocData;

    if (data == null || data['username'] == null) {
      return const UsernameScreen();
    }

    // Fire-and-forget; the guard inside makes it a no-op after the first call.
    _initNotificationsForUser(_user!.uid);
    _checkPendingInvite(_user!.uid);

    if (_pendingInviteLinkId != null) {
      return InviteRedeemScreen(
        linkId: _pendingInviteLinkId!,
        onDone: () => setState(() => _pendingInviteLinkId = null),
      );
    }

    return CelebrationGate(uid: _user!.uid, child: const HomeScreen());
  }
}
