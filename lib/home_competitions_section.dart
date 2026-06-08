import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/firestore_service.dart';
import 'competition_details_screen.dart';

class HomeCompetitionsSection extends StatelessWidget {
  final String uid;
  final _firestoreService = FirestoreService();

  HomeCompetitionsSection({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestoreService.getUserCompetitions(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          debugPrint('My competitions error: ${snapshot.error}');
          return Text('Error: ${snapshot.error}');
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const Text('No competitions yet');
        }

        return Column(
          children: docs.map((doc) {
            final competition = doc.data();
            final competitionId = doc.id;
            final title = competition['title'] ?? '';
            final description = competition['description'] ?? '';
            final status = competition['status'] ?? '';
            final type = competition['type'] ?? '';
            final createdBy = competition['createdBy'] ?? '';

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CompetitionDetailsScreen(
                      competitionId: competitionId,
                      title: title,
                      description: description,
                      status: status,
                      createdBy: createdBy,
                    ),
                  ),
                );
              },
              child: Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (description.toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(description),
                      ],
                      const SizedBox(height: 12),
                      Text('Type: $type'),
                      const SizedBox(height: 4),
                      Text('Status: $status'),
                      const SizedBox(height: 16),
                      const Text(
                        'Participants',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      _ParticipantsList(
                        competitionId: competitionId,
                        currentUid: uid,
                        firestoreService: _firestoreService,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _ParticipantsList extends StatelessWidget {
  final String competitionId;
  final String currentUid;
  final FirestoreService firestoreService;

  const _ParticipantsList({
    required this.competitionId,
    required this.currentUid,
    required this.firestoreService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestoreService.getCompetitionParticipants(competitionId),
      builder: (context, participantsSnapshot) {
        if (participantsSnapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (participantsSnapshot.hasError) {
          debugPrint('Participants stream error: ${participantsSnapshot.error}');
          return Text('Error: ${participantsSnapshot.error}');
        }

        final participantDocs = participantsSnapshot.data?.docs ?? [];

        if (participantDocs.isEmpty) {
          return const Text('No participants yet');
        }

        final participants = participantDocs.map((doc) => doc.data()).toList();

        participants.sort((a, b) {
          final progressA = a['progress'] ?? 0;
          final progressB = b['progress'] ?? 0;
          final targetA = a['targetValue'] ?? 0;
          final targetB = b['targetValue'] ?? 0;

          final percentA = targetA > 0 ? progressA / targetA : 0.0;
          final percentB = targetB > 0 ? progressB / targetB : 0.0;

          return percentB.compareTo(percentA);
        });

        return Column(
          children: participants.map((participant) {
            final username = participant['username'] ?? '';
            final uid = participant['uid'] ?? '';
            final progress = participant['progress'] ?? 0;
            final targetValue = participant['targetValue'] ?? 0;
            final goalTitle = participant['goalTitle'] ?? '';
            final unit = participant['unit'] ?? '';

            final name = username.toString().isNotEmpty ? username : uid;
            final isMe = uid == currentUid;
            final progressValue = targetValue > 0 ? (progress / targetValue) : 0.0;
            final progressBarValue = progressValue.clamp(0.0, 1.0);
            final percentText = targetValue > 0
                ? '${(progressValue * 100).toStringAsFixed(0)}%'
                : '0%';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isMe ? '$name (You)' : name,
                          style: TextStyle(
                            fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        percentText,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  if (goalTitle.toString().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(goalTitle),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    '$progress / $targetValue ${unit.toString()}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (isMe) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: () async {
                          try {
                            await firestoreService.incrementMyProgress(
                              competitionId: competitionId,
                              uid: currentUid,
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error updating progress: $e')),
                            );
                          }
                        },
                        icon: const Icon(Icons.add_circle),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: progressBarValue,
                    minHeight: 18,
                    borderRadius: const BorderRadius.all(Radius.circular(7)),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
