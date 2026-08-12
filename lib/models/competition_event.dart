import 'package:cloud_firestore/cloud_firestore.dart';

class CompetitionEvent {
  final String id;
  final String competitionId;
  final String type;
  final String? actorUsername;
  final String? targetUsername;
  final Timestamp? lastUpdatedAt;
  final Map<String, dynamic>? metadata;

  CompetitionEvent({
    required this.id,
    required this.competitionId,
    required this.type,
    this.actorUsername,
    this.targetUsername,
    this.lastUpdatedAt,
    this.metadata,
  });

  factory CompetitionEvent.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return CompetitionEvent(
      id: doc.id,
      competitionId: data['competitionId'] as String? ?? '',
      type: data['type'] as String? ?? '',
      actorUsername: data['actorUsername'] as String?,
      targetUsername: data['targetUsername'] as String?,
      lastUpdatedAt: (data['lastUpdatedAt'] ?? data['createdAt']) as Timestamp?,
      metadata: data['metadata'] as Map<String, dynamic>?,
    );
  }
}
