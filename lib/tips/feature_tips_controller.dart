import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'feature_tip.dart';

/// Which first-time feature tips the signed-in user has already seen.
///
/// Persisted as `users/{uid}.seenTips` (`{tipId: true}`). Like the streak,
/// this is cosmetic, client-written state: it only decides whether a short
/// explanation is shown, so it's written directly rather than through a
/// callable.
class FeatureTipsController extends ChangeNotifier {
  FeatureTipsController._();
  static final FeatureTipsController instance = FeatureTipsController._();

  static const firestoreField = 'seenTips';

  /// Tracks which page the user is on, so FeatureTipLayer can keep to one
  /// tip per screen visit. Registered on MaterialApp.navigatorObservers.
  final PageVisitObserver pageVisits = PageVisitObserver();

  String? _uid;

  /// Null until loaded — and no tips are shown until then.
  Set<String>? _seen;

  /// Bumped on every user change, so a load started for a previous user
  /// can't land on the current one.
  int _session = 0;

  bool get isReady => _uid != null && _seen != null;

  /// The tips still owed to this user, in priority order. Empty until the
  /// seen set has loaded.
  List<FeatureTip> get pending {
    final seen = _seen;
    if (_uid == null || seen == null) return const [];
    return [
      for (final tip in FeatureTip.values)
        if (!seen.contains(tip.id)) tip,
    ];
  }

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  /// Called when the user reaches Home.
  Future<void> attachUser(String uid) async {
    if (_uid == uid) return;
    _session++;
    _uid = uid;
    _seen = null;
    final session = _session;
    try {
      final doc = await _userDoc(uid).get();
      if (session != _session) return;
      final raw = doc.data()?[firestoreField];
      _seen = {
        if (raw is Map)
          for (final entry in raw.entries)
            if (entry.value == true) entry.key as String,
      };
      notifyListeners();
    } catch (e) {
      // Fail closed: without knowing what was seen, show nothing rather
      // than repeat tips. Clearing _uid lets the next Home entry retry.
      debugPrint('Feature tips load error: $e');
      if (session == _session) _uid = null;
    }
  }

  /// Called on sign-out.
  void reset() {
    _session++;
    _uid = null;
    _seen = null;
    notifyListeners();
  }

  void markSeen(FeatureTip tip) {
    final uid = _uid;
    final seen = _seen;
    if (uid == null || seen == null || !seen.add(tip.id)) return;
    notifyListeners();
    // Not awaited: Firestore only resolves on server ack, and the local set
    // is already updated; the write lands when connectivity returns.
    unawaited(
      _userDoc(uid)
          .set({
            firestoreField: {tip.id: true},
          }, SetOptions(merge: true))
          .catchError((Object e) => debugPrint('Feature tip save error: $e')),
    );
  }

  /// Debug builds only (Home app bar): makes every tip show again.
  Future<void> debugResetAll() async {
    final uid = _uid;
    if (uid == null) return;
    _seen = {};
    notifyListeners();
    await _userDoc(uid).update({firestoreField: FieldValue.delete()});
  }
}

/// Counts visits to full-screen pages: [visit] changes whenever the
/// top-most [PageRoute] changes. Dialogs and bottom sheets opening over a
/// page don't count as leaving it.
class PageVisitObserver extends NavigatorObserver with ChangeNotifier {
  final List<Route<dynamic>> _stack = [];
  Route<dynamic>? _topPage;
  int _visit = 0;

  int get visit => _visit;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (newRoute != null) {
      if (index >= 0) {
        _stack[index] = newRoute;
      } else {
        _stack.add(newRoute);
      }
    } else if (index >= 0) {
      _stack.removeAt(index);
    }
    _update();
  }

  void _update() {
    Route<dynamic>? top;
    for (final route in _stack.reversed) {
      if (route is PageRoute) {
        top = route;
        break;
      }
    }
    if (identical(top, _topPage)) return;
    _topPage = top;
    _visit++;
    notifyListeners();
  }
}
