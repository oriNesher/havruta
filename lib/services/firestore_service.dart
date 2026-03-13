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

  /// Add new participant to an existing competition
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
}
