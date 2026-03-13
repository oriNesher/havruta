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

  /// Create a new competition
  Future<void> createCompetition({
    required String title,
    required String description,
    required int targetNumber,
    required String unit,
    required String createdBy,
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
      'progress': 0,
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }

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

  /// Add new participant to an existing
  Future<void> addParticipant({
    required String competitionId,
    required String uid,
  }) async {
    final competitionRef = _db.collection('competitions').doc(competitionId);

    await competitionRef.update({
      'participantUids': FieldValue.arrayUnion([uid]),
    });

    await competitionRef.collection('participants').doc(uid).set({
      'uid': uid,
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

  /// Update progress of participant by given one
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

  /// Send an invite
  Future<void> sendCompetitionInvite({
    required String competitionId,
    required String competitionTitle,
    required String fromUid,
    required String toUid,
  }) async {
    await _db.collection('competition_invites').add({
      'competitionId': competitionId,
      'competitionTitle': competitionTitle,
      'fromUid': fromUid,
      'toUid': toUid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get all your invites
  Stream<QuerySnapshot<Map<String, dynamic>>> getPendingInvites(String uid) {
    return _db
        .collection('competition_invites')
        .where('toUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  /// accept an invite
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

  /// decline an invite
  Future<void> declineCompetitionInvite({required String inviteId}) async {
    await _db.collection('competition_invites').doc(inviteId).update({
      'status': 'declined',
    });
  }

  /// get username from uid
  Future<String?> getMyUsername(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    return data?['username'];
  }

  /// Search users by usernames (in lower case)
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

  /// Check if there is already such invite 
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
}
