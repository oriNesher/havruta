import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'onboarding_ids.dart';
import 'onboarding_state.dart';

/// Firestore/Functions access for the onboarding tutorial. Reads the real
/// onboarding records startOnboarding creates; the only thing it writes
/// directly is the user's own cosmetic tutorial-progress map.
class OnboardingRepository {
  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;

  CollectionReference<Map<String, dynamic>> get _invites =>
      _db.collection('competition_invites');

  // ── Tutorial progress (users/{uid}.onboardingTutorial) ────────────────

  Future<OnboardingTutorialState> loadState(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final raw = doc.data()?[OnboardingTutorialState.firestoreField];
    return OnboardingTutorialState.fromMap(
      raw is Map ? Map<String, dynamic>.from(raw) : null,
    );
  }

  Future<void> saveState(String uid, OnboardingTutorialState state) {
    return _db.collection('users').doc(uid).set({
      OnboardingTutorialState.firestoreField: {
        ...state.toMap(),
        'version': OnboardingTutorialState.schemaVersion,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  Future<void> clearState(String uid) {
    return _db.collection('users').doc(uid).update({
      OnboardingTutorialState.firestoreField: FieldValue.delete(),
    });
  }

  // ── Onboarding challenges/invites (server-owned) ──────────────────────

  /// Calls the idempotent startOnboarding callable and returns the invite
  /// id it created or reused for each onboarding challenge.
  Future<Map<OnboardingChallengeKey, String>> startOnboarding() async {
    final result = await _functions
        .httpsCallable('startOnboarding')
        .call<Map<dynamic, dynamic>>();
    final challenges = Map<String, dynamic>.from(
      result.data['challenges'] as Map,
    );
    return {
      for (final key in OnboardingChallengeKey.values)
        if (challenges[key.name] is Map)
          key: (challenges[key.name] as Map)['inviteId'] as String,
    };
  }

  /// Confirms against the server (not the local cache) that each invite
  /// exists and is a genuine onboarding invite for [uid]. Retries briefly,
  /// since this runs right after startOnboarding returns.
  Future<void> confirmInvitesExist(
    String uid,
    Iterable<String> inviteIds,
  ) async {
    for (final id in inviteIds) {
      var confirmed = false;
      for (var attempt = 0; attempt < 4 && !confirmed; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
        final snap = await _invites
            .doc(id)
            .get(const GetOptions(source: Source.server));
        final data = snap.data();
        confirmed = data != null && isOnboardingInviteFor(data, uid);
      }
      if (!confirmed) {
        throw StateError('Onboarding invite $id could not be confirmed');
      }
    }
  }

  /// The onboarding invite ids for [uid], from the onboarding_state ledger
  /// startOnboarding writes, falling back to the deterministic ids.
  Future<Map<OnboardingChallengeKey, String>> onboardingInviteIds(
    String uid,
  ) async {
    final ids = {
      for (final key in OnboardingChallengeKey.values)
        key: onboardingInviteId(uid, key),
    };
    try {
      final ledger = await _db.collection('onboarding_state').doc(uid).get();
      final challenges = ledger.data()?['challenges'];
      if (challenges is Map) {
        for (final key in OnboardingChallengeKey.values) {
          final entry = challenges[key.name];
          final id = entry is Map ? entry['inviteId'] : null;
          if (id is String) ids[key] = id;
        }
      }
    } catch (e) {
      debugPrint('Onboarding ledger read error (using deterministic ids): $e');
    }
    return ids;
  }

  /// Live invite doc, including local-write metadata so callers can tell a
  /// still-in-flight accept apart from a server-confirmed one.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchInvite(String id) {
    return _invites.doc(id).snapshots(includeMetadataChanges: true);
  }

  /// Identity check for onboarding invites: explicit metadata plus the
  /// recipient, never the display title.
  static bool isOnboardingInviteFor(Map<String, dynamic> data, String uid) {
    final meta = data['onboarding'];
    return data['toUid'] == uid &&
        meta is Map &&
        meta['isOnboarding'] == true &&
        meta['onboardingUserId'] == uid;
  }

  // ── TEMPORARY (debug harness only) ────────────────────────────────────

  /// TEMPORARY: deletes the caller's onboarding challenges, invites, and
  /// ledger server-side so Module 1 can be replayed from pending invites.
  /// Remove together with lib/debug/onboarding_debug_screen.dart.
  Future<Map<String, dynamic>> resetOnboardingForTesting() async {
    final result = await _functions
        .httpsCallable('resetOnboardingForTesting')
        .call<Map<dynamic, dynamic>>();
    return Map<String, dynamic>.from(result.data);
  }
}
