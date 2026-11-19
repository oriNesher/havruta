import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Every organizer power. All of them except the "paid" flag go through
/// a Cloud Functions callable (functions/src/organizer/) that checks the
/// caller is an organizer, applies the change in a transaction and writes
/// the audit log — firestore.rules give organizers no direct writes beyond
/// renaming and the paid flag.
class OrganizerService {
  final _functions = FirebaseFunctions.instance;
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _challenge(String id) =>
      _db.collection('competitions').doc(id);

  Future<Map<String, dynamic>> _call(
    String name,
    String competitionId,
    Map<String, dynamic> data,
  ) async {
    final result = await _functions.httpsCallable(name).call<Object?>({
      'competitionId': competitionId,
      ...data,
    });
    final payload = result.data;
    return payload is Map ? Map<String, dynamic>.from(payload) : {};
  }

  /// Edit after launch. Pass only what changed; [clearEndsAt] removes the
  /// end date. The server decides what's allowed when (planSettingsChange).
  Future<void> updateSettings(
    String competitionId, {
    String? title,
    String? description,
    DateTime? startsAt,
    DateTime? endsAt,
    bool clearEndsAt = false,
    int? dailyMinimum,
    int? targetValue,
  }) => _call('updateChallengeSettings', competitionId, {
    'title': ?title,
    'description': ?description,
    if (startsAt != null) 'startsAtMillis': startsAt.millisecondsSinceEpoch,
    if (clearEndsAt)
      'endsAtMillis': null
    else if (endsAt != null)
      'endsAtMillis': endsAt.millisecondsSinceEpoch,
    'dailyMinimum': ?dailyMinimum,
    'targetValue': ?targetValue,
  });

  Future<void> correctProgress(
    String competitionId, {
    required String uid,
    required int progress,
    required String dayKey,
    required String reason,
  }) => _call('correctProgress', competitionId, {
    'uid': uid,
    'progress': progress,
    'dayKey': dayKey,
    'reason': reason,
  });

  Future<void> removeParticipant(
    String competitionId, {
    required String uid,
    String reason = '',
  }) => _call('removeParticipant', competitionId, {
    'uid': uid,
    'reason': reason,
  });

  Future<void> reinstateParticipant(
    String competitionId, {
    required String uid,
    required String reason,
  }) => _call('reinstateParticipant', competitionId, {
    'uid': uid,
    'reason': reason,
  });

  /// Ends the challenge now; returns the winners.
  Future<List<String>> endEarly(String competitionId, {String reason = ''}) async {
    final result = await _call('endChallengeEarly', competitionId, {
      'reason': reason,
    });
    return (result['winnerUids'] as List? ?? []).whereType<String>().toList();
  }

  Future<void> addOrganizer(String competitionId, String uid) =>
      _call('setOrganizers', competitionId, {'add': uid});

  Future<void> removeOrganizer(String competitionId, String uid) =>
      _call('setOrganizers', competitionId, {'remove': uid});

  /// Sends to everyone in the challenge; returns how many people.
  Future<int> sendAnnouncement(String competitionId, String text) async {
    final result = await _call('sendAnnouncement', competitionId, {
      'text': text,
    });
    return (result['recipientCount'] as num?)?.toInt() ?? 0;
  }

  /// The manual "paid" flag (fees are collected outside the app during the
  /// pilot). Organizer-only data, written directly; firestore.rules require
  /// the who/when stamp.
  Future<void> setPaid(String competitionId, String uid, bool paid) {
    return _challenge(competitionId).collection('organizerData').doc(uid).set({
      'paid': paid,
      'paidUpdatedBy': FirebaseAuth.instance.currentUser?.uid,
      'paidUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> organizerData(
    String competitionId,
  ) => _challenge(competitionId).collection('organizerData').snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> announcements(
    String competitionId, {
    int limit = 50,
  }) => _challenge(competitionId)
      .collection('announcements')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> auditLog(
    String competitionId,
  ) => _challenge(competitionId)
      .collection('auditLog')
      .orderBy('at', descending: true)
      .limit(300)
      .snapshots();
}

/// A callable's failure as something fit to show an organizer: the
/// server's own message for refusals (they're written for people).
String organizerErrorMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    return error.message ?? 'Something went wrong (${error.code}).';
  }
  if (error is FirebaseException) {
    return error.message ?? 'Something went wrong (${error.code}).';
  }
  return 'Something went wrong: $error';
}
