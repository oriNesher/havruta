import 'package:cloud_firestore/cloud_firestore.dart';

class CompetitionEvent {
  final String id;
  final String competitionId;
  final String type;
  final String? actorUsername;
  final String? targetUsername;
  final Timestamp? lastUpdatedAt;

  CompetitionEvent({
    required this.id,
    required this.competitionId,
    required this.type,
    this.actorUsername,
    this.targetUsername,
    this.lastUpdatedAt,
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
    );
  }
}

/// Groups events by competition, keeping at most one per competition:
/// the most relevant (an 'overtook' event, if any) among the most recent.
Map<String, CompetitionEvent> groupEventsByCompetition(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final result = <String, CompetitionEvent>{};
  for (final doc in docs) {
    final event = CompetitionEvent.fromDoc(doc);
    if (event.competitionId.isEmpty) continue;

    final existing = result[event.competitionId];
    if (existing == null || (event.type == 'overtook' && existing.type != 'overtook')) {
      result[event.competitionId] = event;
    }
  }
  return result;
}
