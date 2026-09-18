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
  CollectionReference<Map<String, dynamic>> get _competitions =>
      _db.collection('competitions');

  /// Event types the Events pipeline fires when a participant reaches their
  /// full target (functions/src/events/rules/progression.ts): "won" for the
  /// first to finish, "finishedInPosition" for everyone after.
  static const completionEventTypes = ['won', 'finishedInPosition'];

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

  /// The onboarding challenge's competition id for [uid], from the
  /// onboarding_state ledger, falling back to the deterministic id.
  Future<String> onboardingCompetitionIdFor(
    String uid,
    OnboardingChallengeKey key,
  ) async {
    try {
      final ledger = await _db.collection('onboarding_state').doc(uid).get();
      final challenges = ledger.data()?['challenges'];
      final entry = challenges is Map ? challenges[key.name] : null;
      final id = entry is Map ? entry['competitionId'] : null;
      if (id is String) return id;
    } catch (e) {
      debugPrint('Onboarding ledger read error (using deterministic id): $e');
    }
    return onboardingCompetitionId(uid, key);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchCompetition(String id) {
    return _competitions.doc(id).snapshots();
  }

  /// Live participant doc, including local-write metadata so callers can
  /// tell an optimistic progress increment apart from a server-confirmed
  /// one.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchParticipant(
    String competitionId,
    String uid,
  ) {
    return _competitions
        .doc(competitionId)
        .collection('participants')
        .doc(uid)
        .snapshots(includeMetadataChanges: true);
  }

  /// Live "reached the target" events in one competition. These are only
  /// ever written by Cloud Functions, so any doc here is real pipeline
  /// output; callers filter by actor.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchCompletionEvents(
    String competitionId,
  ) {
    return _competitions
        .doc(competitionId)
        .collection('events')
        .where('type', whereIn: completionEventTypes)
        .snapshots();
  }

  /// Identity check for an onboarding challenge: explicit metadata (which
  /// challenge, and whose), never the display title.
  static bool isOnboardingChallengeFor(
    Map<String, dynamic> data,
    String uid,
    OnboardingChallengeKey key,
  ) {
    final meta = data['onboarding'];
    return meta is Map &&
        meta['isOnboarding'] == true &&
        meta['onboardingUserId'] == uid &&
        meta['onboardingChallengeKey'] == key.name;
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

  /// TEMPORARY: by default deletes the caller's onboarding challenges,
  /// invites, and ledger server-side so Module 1 can be replayed from
  /// pending invitations. With [scope] `acceptInvitesProgress` it instead
  /// only rewinds Challenge A to "accepted, no progress" (progress 0, its
  /// events deleted) so the Part 3 win can be replayed.
  /// Remove together with lib/debug/onboarding_debug_screen.dart.
  Future<Map<String, dynamic>> resetOnboardingForTesting({
    String? scope,
  }) async {
    final result = await _functions
        .httpsCallable('resetOnboardingForTesting')
        .call<Map<dynamic, dynamic>>({if (scope != null) 'scope': scope});
    return Map<String, dynamic>.from(result.data);
  }
}
