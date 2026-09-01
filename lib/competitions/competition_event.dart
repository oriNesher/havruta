import 'package:cloud_firestore/cloud_firestore.dart';

class CompetitionEvent {
  final String id;
  final String competitionId;
  final String? competitionTitle;
  final String type;
  final String? actorUid;
  final String? actorUsername;
  final String? targetUid;
  final String? targetUsername;
  final Timestamp? createdAt;
  final Timestamp? lastUpdatedAt;
  final Map<String, dynamic>? metadata;
  final List<String> unseenByUserUids;
  final String? batchId;
  final bool actorCelebrated;
  final List<String> respectGivenBy;
  final DocumentReference<Map<String, dynamic>> reference;

  CompetitionEvent({
    required this.id,
    required this.competitionId,
    this.competitionTitle,
    required this.type,
    this.actorUid,
    this.actorUsername,
    this.targetUid,
    this.targetUsername,
    this.createdAt,
    this.lastUpdatedAt,
    this.metadata,
    this.unseenByUserUids = const [],
    this.batchId,
    this.actorCelebrated = true,
    this.respectGivenBy = const [],
    required this.reference,
  });

  factory CompetitionEvent.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return CompetitionEvent(
      id: doc.id,
      competitionId: data['competitionId'] as String? ?? '',
      competitionTitle: data['competitionTitle'] as String?,
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
      batchId: data['batchId'] as String?,
      // Defaults true for event types that never carry this field (only
      // celebration-eligible types do), so they're inert to any code that
      // filters on "not yet celebrated".
      actorCelebrated: data['actorCelebrated'] as bool? ?? true,
      respectGivenBy:
          (data['respectGivenBy'] as List?)?.cast<String>() ?? const [],
      reference: doc.reference,
    );
  }
}
