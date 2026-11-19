import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../competitions/challenge.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Live user doc — backs the Home screen's Respect balance display, which
  /// needs to react the instant a spend or a daily grant lands.
  Stream<DocumentSnapshot<Map<String, dynamic>>> getUserDoc(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  /// "X gave you N Respect" notifications, newest first, for the
  /// notifications screen.
  Stream<QuerySnapshot<Map<String, dynamic>>> getRespectNotifications(
    String uid,
  ) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('respectNotifications')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  /// Get username from uid
  Future<String?> getMyUsername(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    return data?['username'];
  }

  /// Create a new challenge. Everyone shares one goal; [winCondition]
  /// decides how it's won. [targetValue] is the race's finish line (races
  /// only); [rules] carries the daily minimum for Last One Standing.
  /// Returns the new competition ID.
  Future<String> createChallenge({
    required String title,
    required String description,
    required String createdBy,
    required String creatorUsername,
    required WinCondition winCondition,
    required String goalTitle,
    required String unit,
    int? targetValue,
    ChallengeRules rules = const ChallengeRules(),
    String? prize,
    String? timeZone,
    DateTime? startsAt,
    DateTime? endsAt,
    String? linkedGoalTitle,
  }) async {
    final isRace = winCondition == WinCondition.firstToTarget;

    final competitionRef = await _db.collection('competitions').add({
      'title': title,
      'description': description,
      'createdBy': createdBy,
      'participantUids': [createdBy],
      'status': 'active',
      'winnerUid': null,
      'winCondition': winCondition.name,
      // Still written so installed builds from before win conditions read
      // every new challenge as the shared-goal challenge it most resembles.
      'type': 'sharedGoalChallenge',
      'sharedGoalTitle': goalTitle,
      if (isRace && targetValue != null) 'sharedTargetValue': targetValue,
      'sharedUnit': unit,
      if (rules.toMap().isNotEmpty) 'rules': rules.toMap(),
      'prize': ?prize,
      'timeZone': ?timeZone,
      if (startsAt != null) 'startsAt': Timestamp.fromDate(startsAt),
      if (endsAt != null) ...{
        'endsAt': Timestamp.fromDate(endsAt),
        // Legacy display field; older builds' "Nd left" chip parses it.
        'deadline': endsAt.toIso8601String().substring(0, 10),
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    await competitionRef.collection('participants').doc(createdBy).set({
      'uid': createdBy,
      'username': creatorUsername,
      'goalTitle': goalTitle,
      if (isRace && targetValue != null) 'targetValue': targetValue,
      'unit': unit,
      'progress': 0,
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'linkedGoalTitle': ?linkedGoalTitle,
    });

    await _db.collection('users').doc(createdBy).update({
      'lastCompetitionCreatedAt': FieldValue.serverTimestamp(),
    });

    return competitionRef.id;
  }

  /// Get competitions that the user participates in
  Stream<QuerySnapshot<Map<String, dynamic>>> getUserCompetitions(String uid) {
    return _db
        .collection('competitions')
        .where('participantUids', arrayContains: uid)
        .snapshots();
  }

  /// Get a single competition by id
  Future<DocumentSnapshot<Map<String, dynamic>>> getCompetition(
    String competitionId,
  ) {
    return _db.collection('competitions').doc(competitionId).get();
  }

  /// Live competition doc — backs Challenge Details, which must reflect a
  /// challenge completing (or its winner being decided) while it's open.
  Stream<DocumentSnapshot<Map<String, dynamic>>> getCompetitionDoc(
    String competitionId,
  ) {
    return _db.collection('competitions').doc(competitionId).snapshots();
  }

  /// Get participants of a competition
  Stream<QuerySnapshot<Map<String, dynamic>>> getCompetitionParticipants(
    String competitionId,
  ) {
    return _db
        .collection('competitions')
        .doc(competitionId)
        .collection('participants')
        .snapshots();
  }

  /// Lower a participant's progress to [progress] (the edit dialog only
  /// ever reduces it). [dayReductions] is how much of the cut comes off
  /// each challenge day's dailyProgress bucket (see windowDayReductions) —
  /// only recent days, and only today in Last One Standing, whose past
  /// days a daily-minimum rule may already have judged.
  Future<void> updateProgress({
    required String competitionId,
    required String uid,
    required int progress,
    Map<String, int> dayReductions = const {},
  }) async {
    await _db
        .collection('competitions')
        .doc(competitionId)
        .collection('participants')
        .doc(uid)
        .update({
          'progress': progress,
          'updatedAt': FieldValue.serverTimestamp(),
          for (final MapEntry(key: day, value: cut) in dayReductions.entries)
            if (cut > 0)
              FieldPath(['dailyProgress', day]): FieldValue.increment(-cut),
        });
  }

  /// Report progress as a single delta. One call is one Firestore write,
  /// so a report of +30 (whether from a bulk action or several rapid taps
  /// batched together client-side) reaches the backend as one document
  /// update — the event triggers evaluate milestones, overtakes, and
  /// completion off that single before/after change. The same write
  /// credits the challenge-calendar day [dayKey] (Challenge.dayKey), which
  /// daily-minimum rules judge from.
  Future<void> addProgress({
    required String competitionId,
    required String uid,
    required int amount,
    required String dayKey,
  }) async {
    await _db
        .collection('competitions')
        .doc(competitionId)
        .collection('participants')
        .doc(uid)
        .update({
          'progress': FieldValue.increment(amount),
          'updatedAt': FieldValue.serverTimestamp(),
          // A FieldPath, not 'dailyProgress.$dayKey': the dashes in the
          // date aren't valid in a dotted field-path string.
          FieldPath(['dailyProgress', dayKey]): FieldValue.increment(amount),
        });
  }

  /// Search users by usernameLower
  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> findUserByUsername(
    String username,
  ) async {
    final result = await _db
        .collection('users')
        .where('usernameLower', isEqualTo: username.toLowerCase())
        .limit(1)
        .get();

    if (result.docs.isEmpty) return null;
    return result.docs.first;
  }

  /// Live prefix search on usernameLower, for as-you-type search fields.
  /// Deliberately not offered for email (prefix search on email would let
  /// someone enumerate registered addresses character by character).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  searchUsersByUsernamePrefix(String prefix, {int limit = 8}) async {
    final normalized = prefix.trim().toLowerCase();
    if (normalized.isEmpty) return [];

    final result = await _db
        .collection('users')
        .where('usernameLower', isGreaterThanOrEqualTo: normalized)
        .where('usernameLower', isLessThan: '$normalized')
        .limit(limit)
        .get();

    return result.docs;
  }

  /// Search users by emailLower
  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> findUserByEmail(
    String email,
  ) async {
    final result = await _db
        .collection('users')
        .where('emailLower', isEqualTo: email.toLowerCase())
        .limit(1)
        .get();

    if (result.docs.isEmpty) return null;
    return result.docs.first;
  }

  /// Check if there is already a pending invite for this user in this competition
  Future<bool> inviteAlreadyExists({
    required String competitionId,
    required String toUid,
  }) async {
    final result = await _db
        .collection('competition_invites')
        .where('competitionId', isEqualTo: competitionId)
        .where('toUid', isEqualTo: toUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    return result.docs.isNotEmpty;
  }

  /// Send an invite. Copies the challenge's definition onto the invite so
  /// the recipient's accept card can describe it without another read.
  Future<void> sendCompetitionInvite({
    required Challenge challenge,
    required String fromUid,
    required String toUid,
    required String toUsername,
  }) async {
    await _db.collection('competition_invites').add({
      'competitionId': challenge.id,
      'competitionTitle': challenge.title,
      'competitionType': challenge.isLegacyPersonal
          ? 'personalGoalChallenge'
          : 'sharedGoalChallenge',
      if (!challenge.isLegacyPersonal) ...{
        'winCondition': challenge.winCondition.name,
        'sharedGoalTitle': challenge.goalTitle,
        'sharedTargetValue': ?challenge.targetValue,
        'sharedUnit': challenge.unit,
        if (challenge.rules.toMap().isNotEmpty)
          'rules': challenge.rules.toMap(),
      },
      'fromUid': fromUid,
      'toUid': toUid,
      'toUsername': toUsername,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get all your pending invites
  Stream<QuerySnapshot<Map<String, dynamic>>> getPendingInvites(String uid) {
    return _db
        .collection('competition_invites')
        .where('toUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  /// Get all pending invites for a specific competition
  Stream<QuerySnapshot<Map<String, dynamic>>> getCompetitionPendingInvites(
    String competitionId,
  ) {
    return _db
        .collection('competition_invites')
        .where('competitionId', isEqualTo: competitionId)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  /// Accept an invite to a legacy Personal Goal challenge, defining the
  /// joiner's own goal. Only reachable from invites sent before win
  /// conditions; remove once those have all been answered.
  Future<void> acceptCompetitionInvite({
    required String inviteId,
    required String competitionId,
    required String uid,
    required String username,
    required String goalTitle,
    required int targetValue,
    required String unit,
  }) async {
    final competitionRef = _db.collection('competitions').doc(competitionId);
    final participantRef = competitionRef.collection('participants').doc(uid);
    final inviteRef = _db.collection('competition_invites').doc(inviteId);

    try {
      final batch = _db.batch();

      batch.update(competitionRef, {
        'participantUids': FieldValue.arrayUnion([uid]),
      });

      batch.set(participantRef, {
        'uid': uid,
        'username': username,
        'goalTitle': goalTitle,
        'targetValue': targetValue,
        'unit': unit,
        'progress': 0,
        'joinedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.update(inviteRef, {'status': 'accepted'});

      await batch.commit();
    } catch (e, st) {
      debugPrint('ACCEPT_INVITE_SERVICE: ERROR -> $e');
      debugPrint('ACCEPT_INVITE_SERVICE: STACK TRACE: $st');
      rethrow;
    }
  }

  /// Accept a challenge invite. The participant is added with the
  /// challenge's shared goal; [targetValue] is the race finish line, null
  /// for modes without one.
  Future<void> acceptChallengeInvite({
    required String inviteId,
    required String competitionId,
    required String uid,
    required String username,
    required String goalTitle,
    required int? targetValue,
    required String unit,
  }) async {
    final competitionRef = _db.collection('competitions').doc(competitionId);
    final participantRef = competitionRef.collection('participants').doc(uid);
    final inviteRef = _db.collection('competition_invites').doc(inviteId);

    final batch = _db.batch();

    batch.update(competitionRef, {
      'participantUids': FieldValue.arrayUnion([uid]),
    });

    batch.set(participantRef, {
      'uid': uid,
      'username': username,
      'goalTitle': goalTitle,
      'targetValue': ?targetValue,
      'unit': unit,
      'progress': 0,
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.update(inviteRef, {'status': 'accepted'});

    await batch.commit();
  }

  /// Decline an invite
  Future<void> declineCompetitionInvite({required String inviteId}) async {
    await _db.collection('competition_invites').doc(inviteId).update({
      'status': 'declined',
    });
  }

  /// Delete competition (only creator should be allowed from UI / rules)
  ///
  /// The competition doc is deleted first, before its participants, so that
  /// participant-deletion triggers can tell "competition ending" apart from
  /// "participant leaving one that continues" by checking whether the
  /// competition doc still exists.
  Future<void> deleteCompetition(String competitionId) async {
    final competitionRef = _db.collection('competitions').doc(competitionId);

    await competitionRef.delete();

    final participantsSnapshot = await competitionRef
        .collection('participants')
        .get();

    for (final doc in participantsSnapshot.docs) {
      await doc.reference.delete();
    }

    final invitesSnapshot = await _db
        .collection('competition_invites')
        .where('competitionId', isEqualTo: competitionId)
        .get();

    for (final doc in invitesSnapshot.docs) {
      await doc.reference.delete();
    }

    // Invite links (and their redemptions) are server-only per
    // firestore.rules; the onCompetitionDeletedCleanupInviteLinks trigger
    // removes them once the competition doc above is gone.
  }

  /// Get username by uid
  Future<String?> getUsernameByUid(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    return data?['username'] as String?;
  }

  Future<bool> isAlreadyParticipant({
    required String competitionId,
    required String uid,
  }) async {
    final doc = await _db
        .collection('competitions')
        .doc(competitionId)
        .collection('participants')
        .doc(uid)
        .get();

    return doc.exists;
  }

  /// Get the most recent events for a single competition, newest first.
  /// Backs the home card's event carousel.
  Stream<QuerySnapshot<Map<String, dynamic>>> getCompetitionEvents(
    String competitionId,
  ) {
    return _db
        .collection('competitions')
        .doc(competitionId)
        .collection('events')
        .orderBy('lastUpdatedAt', descending: true)
        .limit(25)
        .snapshots();
  }

  /// Every event created in a competition since [since], oldest first.
  /// Backs the Challenge Details activity graph, which picks the
  /// progress-report events out client-side — filtering on type here
  /// would need a composite (type, createdAt) index for no real saving.
  Stream<QuerySnapshot<Map<String, dynamic>>> getCompetitionActivitySince(
    String competitionId,
    DateTime since,
  ) {
    return _db
        .collection('competitions')
        .doc(competitionId)
        .collection('events')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt')
        .limit(1000)
        .snapshots();
  }

  /// After showing an event, we want to mark it as seen
  Future<void> dismissEventsForUser(
    List<DocumentReference<Map<String, dynamic>>> eventRefs,
    String uid,
  ) async {
    final batch = _db.batch();

    for (final ref in eventRefs) {
      batch.update(ref, {
        'unseenByUserUids': FieldValue.arrayRemove([uid]),
      });
    }

    await batch.commit();
  }

  /// Celebration-eligible events awaiting this user's celebration, across
  /// every competition they're in. Filtering down to celebration types is
  /// left to the caller (kCelebrationTypes) rather than done here, so the
  /// allowlist can change without touching this query.
  Stream<QuerySnapshot<Map<String, dynamic>>> getPendingCelebrations(
    String uid,
  ) {
    return _db
        .collectionGroup('events')
        .where('actorUid', isEqualTo: uid)
        .where('actorCelebrated', isEqualTo: false)
        .snapshots();
  }

  /// Marks a batch of events as celebrated by their actor, once the
  /// celebration + trash talk flow for them has run its course.
  Future<void> markEventsCelebrated(
    List<DocumentReference<Map<String, dynamic>>> eventRefs,
  ) async {
    final batch = _db.batch();

    for (final ref in eventRefs) {
      batch.update(ref, {'actorCelebrated': true});
    }

    await batch.commit();
  }

  /// Get the progress snapshot from the user's last visit for a competition
  Future<Map<String, int>?> getCompetitionSnapshot(
    String uid,
    String competitionId,
  ) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('competitionSnapshots')
        .doc(competitionId)
        .get();

    if (!doc.exists) return null;
    final participants = doc.data()?['participants'] as Map<String, dynamic>?;
    if (participants == null) return null;
    return participants.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  /// Save the current progress snapshot for a competition (called after rendering)
  Future<void> saveCompetitionSnapshot(
    String uid,
    String competitionId,
    Map<String, int> progressMap,
  ) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('competitionSnapshots')
        .doc(competitionId)
        .set({
          'snapshotAt': FieldValue.serverTimestamp(),
          'participants': progressMap,
        });
  }

  /// Get user's bucket goals as a live stream of titles
  Stream<List<String>> getUserGoals(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('goals')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => doc.data()['title'] as String)
                  .toList(),
        );
  }

  /// Check today's date against lastOpenedDate and update the streak.
  /// Returns the current streak count after the update.
  Future<int> checkAndUpdateStreak(String uid) async {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();

    final lastOpened = data?['lastOpenedDate'] as String?;
    final currentStreak = (data?['streakCount'] as num?)?.toInt() ?? 0;

    if (lastOpened == todayStr) return currentStreak;

    int newStreak;
    if (lastOpened != null) {
      final todayMidnight = DateTime(now.year, now.month, now.day);
      final lastDate = DateTime.parse(lastOpened);
      final diff = todayMidnight.difference(lastDate).inDays;
      newStreak = diff == 1 ? currentStreak + 1 : 1;
    } else {
      newStreak = 1;
    }

    await _db.collection('users').doc(uid).update({
      'streakCount': newStreak,
      'lastOpenedDate': todayStr,
    });

    return newStreak;
  }
}
