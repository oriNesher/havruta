import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// Create a new competition
  /// Returns the new competition ID
  Future<String> createCompetition({
    required String title,
    required String description,
    required int targetNumber,
    required String unit,
    required String createdBy,
    required String creatorUsername,
  }) async {
    final competitionRef = await _db.collection('competitions').add({
      'title': title,
      'description': description,
      'targetNumber': targetNumber,
      'unit': unit,
      'createdBy': createdBy,
      'participantUids': [createdBy],
      'status': 'active',
      'winnerUid': null,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await competitionRef.collection('participants').doc(createdBy).set({
      'uid': createdBy,
      'username': creatorUsername,
      'progress': 0,
      'joinedAt': FieldValue.serverTimestamp(),
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
  }) async {
    final competitionRef = _db.collection('competitions').doc(competitionId);

    await competitionRef.update({
      'participantUids': FieldValue.arrayUnion([uid]),
    });

    await competitionRef.collection('participants').doc(uid).set({
      'uid': uid,
      'username': username,
      'progress': 0,
      'joinedAt': FieldValue.serverTimestamp(),
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
        .update({'progress': progress});
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
        .update({'progress': FieldValue.increment(1)});
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

  /// Accept an invite
  Future<void> acceptCompetitionInvite({
    required String inviteId,
    required String competitionId,
    required String uid,
    required String username,
  }) async {
    final competitionRef = _db.collection('competitions').doc(competitionId);
    final inviteRef = _db.collection('competition_invites').doc(inviteId);

    await competitionRef.update({
      'participantUids': FieldValue.arrayUnion([uid]),
    });

    await competitionRef.collection('participants').doc(uid).set({
      'uid': uid,
      'username': username,
      'progress': 0,
      'joinedAt': FieldValue.serverTimestamp(),
    });

    await inviteRef.update({'status': 'accepted'});
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
}
