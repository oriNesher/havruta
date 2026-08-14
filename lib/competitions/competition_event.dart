import 'package:cloud_firestore/cloud_firestore.dart';

class CompetitionEvent {
  final String id;
  final String competitionId;
  final String type;
  final String? actorUid;
  final String? actorUsername;
  final String? targetUid;
  final String? targetUsername;
  final Timestamp? createdAt;
  final Timestamp? lastUpdatedAt;
  final Map<String, dynamic>? metadata;
  final List<String> unseenByUserUids;
  final DocumentReference<Map<String, dynamic>> reference;

  CompetitionEvent({
    required this.id,
    required this.competitionId,
    required this.type,
    this.actorUid,
    this.actorUsername,
    this.targetUid,
    this.targetUsername,
    this.createdAt,
    this.lastUpdatedAt,
    this.metadata,
    this.unseenByUserUids = const [],
    required this.reference,
  });

  factory CompetitionEvent.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return CompetitionEvent(
      id: doc.id,
      competitionId: data['competitionId'] as String? ?? '',
      type: data['type'] as String? ?? '',
      actorUid: data['actorUid'] as String?,
      actorUsername: data['actorUsername'] as String?,
      targetUid: data['targetUid'] as String?,
      targetUsername: data['targetUsername'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
      lastUpdatedAt: (data['lastUpdatedAt'] ?? data['createdAt']) as Timestamp?,
      metadata: data['metadata'] as Map<String, dynamic>?,
      unseenByUserUids:
          (data['unseenByUserUids'] as List?)?.cast<String>() ?? const [],
      reference: doc.reference,
    );
  }
}
