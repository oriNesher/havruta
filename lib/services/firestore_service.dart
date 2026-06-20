import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Create user document in Firestore
  Future<void> createUser({required String uid, required String email}) async {
    await _db.collection('users').doc(uid).set({
      'uid': uid,
      'email': email,
      'username': null,
      'usernameLower': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get user data
  Future<DocumentSnapshot<Map<String, dynamic>>> getUser(String uid) {
    return _db.collection('users').doc(uid).get();
  }

  /// Get username from uid
  Future<String?> getMyUsername(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    return data?['username'];
  }

  /// Create a new personal goal challenge competition
  /// Returns the new competition ID
  Future<String> createCompetition({
    required String title,
    required String description,
    required String createdBy,
    required String creatorUsername,
    required String goalTitle,
    required int targetValue,
    required String unit,
    String? deadline,
    String? linkedGoalTitle,
  }) async {
    final competitionRef = await _db.collection('competitions').add({
      'title': title,
      'description': description,
      'createdBy': createdBy,
      'participantUids': [createdBy],
      'status': 'active',
      'winnerUid': null,
      'type': 'personalGoalChallenge',
      'createdAt': FieldValue.serverTimestamp(),
      if (deadline != null && deadline.isNotEmpty) 'deadline': deadline,
    });

    await competitionRef.collection('participants').doc(createdBy).set({
      'uid': createdBy,
      'username': creatorUsername,
      'goalTitle': goalTitle,
      'targetValue': targetValue,
      'unit': unit,
      'progress': 0,
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (linkedGoalTitle != null) 'linkedGoalTitle': linkedGoalTitle,
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

  /// Get all competitions
  Future<QuerySnapshot<Map<String, dynamic>>> getCompetitions() {
    return _db.collection('competitions').get();
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

  /// Add new participant to an existing competition
  Future<void> addParticipant({
    required String competitionId,
    required String uid,
    required String username,
    required String goalTitle,
    required int targetValue,
    required String unit,
  }) async {
    final competitionRef = _db.collection('competitions').doc(competitionId);

    await competitionRef.update({
      'participantUids': FieldValue.arrayUnion([uid]),
    });

    await competitionRef.collection('participants').doc(uid).set({
      'uid': uid,
      'username': username,
      'goalTitle': goalTitle,
      'targetValue': targetValue,
      'unit': unit,
      'progress': 0,
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update progress of participant by given number
  Future<void> updateProgress({
    required String competitionId,
    required String uid,
    required int progress,
  }) async {
    await _db
        .collection('competitions')
        .doc(competitionId)
        .collection('participants')
        .doc(uid)
        .update({
          'progress': progress,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  /// Update progress of participant by one
  Future<void> incrementMyProgress({
    required String competitionId,
    required String uid,
  }) async {
    await _db
        .collection('competitions')
        .doc(competitionId)
        .collection('participants')
        .doc(uid)
        .update({
          'progress': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  /// Update participant personal goal inside a competition
  Future<void> updateParticipantGoal({
    required String competitionId,
    required String uid,
    required String goalTitle,
    required int targetValue,
    required String unit,
  }) async {
    await _db
        .collection('competitions')
        .doc(competitionId)
        .collection('participants')
        .doc(uid)
        .update({
          'goalTitle': goalTitle,
          'targetValue': targetValue,
          'unit': unit,
          'updatedAt': FieldValue.serverTimestamp(),
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

  /// Send an invite
  Future<void> sendCompetitionInvite({
    required String competitionId,
    required String competitionTitle,
    required String fromUid,
    required String toUid,
    required String toUsername,
  }) async {
    await _db.collection('competition_invites').add({
      'competitionId': competitionId,
      'competitionTitle': competitionTitle,
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

  /// Accept an invite and define personal goal for this competition
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

  /// Decline an invite
  Future<void> declineCompetitionInvite({required String inviteId}) async {
    await _db.collection('competition_invites').doc(inviteId).update({
      'status': 'declined',
    });
  }

  /// Save FCM token for notification service
  Future<void> saveUserFcmToken(String uid, String token) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  /// Delete competition (only creator should be allowed from UI / rules)
  Future<void> deleteCompetition(String competitionId) async {
    final competitionRef = _db.collection('competitions').doc(competitionId);

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

    await competitionRef.delete();
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

  /// Get all events relevant to the user
  Stream<QuerySnapshot<Map<String, dynamic>>> getHomeEvents(String uid) {
    return _db
        .collection('events')
        .where('unseenByUserUids', arrayContains: uid)
        .orderBy('lastUpdatedAt', descending: true)
        .limit(15)
        .snapshots();
  }

  /// After showing an event, we want to mark it as seen
  Future<void> dismissEventsForUser(List<String> eventIds, String uid) async {
    final batch = _db.batch();

    for (final eventId in eventIds) {
      final ref = _db.collection('events').doc(eventId);

      batch.update(ref, {
        'unseenByUserUids': FieldValue.arrayRemove([uid]),
      });
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

  /// Save multiple goals at once (used during onboarding)
  Future<void> addGoalsBatch(String uid, List<String> goals) async {
    final batch = _db.batch();
    final goalsRef = _db.collection('users').doc(uid).collection('goals');

    for (final goal in goals) {
      batch.set(goalsRef.doc(), {
        'title': goal,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  /// Save a single goal to the bucket
  Future<void> addGoal(String uid, String goalTitle) async {
    await _db.collection('users').doc(uid).collection('goals').add({
      'title': goalTitle,
      'createdAt': FieldValue.serverTimestamp(),
    });
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

  /// Mark the goals bucket onboarding step as complete
  Future<void> markGoalsBucketCompleted(String uid) async {
    await _db.collection('users').doc(uid).update({
      'hasCompletedGoalsBucket': true,
    });
  }

  /// Check if a goal already exists in the bucket (case-insensitive exact match)
  Future<bool> goalExistsInBucket(String uid, String goalTitle) async {
    final snapshot =
        await _db.collection('users').doc(uid).collection('goals').get();

    final normalized = goalTitle.trim().toLowerCase();
    return snapshot.docs.any(
      (doc) => (doc.data()['title'] as String).toLowerCase() == normalized,
    );
  }
}
