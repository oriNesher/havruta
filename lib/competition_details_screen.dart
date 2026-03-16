import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'services/firestore_service.dart';
import 'competition_invite_section.dart';

class CompetitionDetailsScreen extends StatelessWidget {
  final String competitionId;
  final String title;
  final String description;
  final int targetNumber;
  final String unit;
  final String status;
  final String createdBy;

  const CompetitionDetailsScreen({
    super.key,
    required this.competitionId,
    required this.title,
    required this.description,
    required this.targetNumber,
    required this.unit,
    required this.status,
    required this.createdBy,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final firestoreService = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Competition Details'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),

              if (description.isNotEmpty) ...[
                Text(
                  'Description',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(description),
                const SizedBox(height: 20),
              ],

              Text(
                'Target',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text('$targetNumber $unit'),
              const SizedBox(height: 20),

              Text(
                'Status',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(status),
              const SizedBox(height: 20),

              Text(
                'Created By',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(createdBy),
              const SizedBox(height: 20),

              Text(
                'Competition ID',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(competitionId),
              const SizedBox(height: 32),

              if (user != null) ...[
                CompetitionInviteSection(
                  competitionId: competitionId,
                  competitionTitle: title,
                  currentUserUid: user.uid,
                ),
                const SizedBox(height: 32),
              ],

              Text(
                'Participants',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),

              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: firestoreService.getCompetitionParticipants(
                  competitionId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return const Text('No participants yet');
                  }

                  final participants = docs.map((doc) => doc.data()).toList();

                  participants.sort((a, b) {
                    final progressA = a['progress'] ?? 0;
                    final progressB = b['progress'] ?? 0;
                    return progressB.compareTo(progressA);
                  });

                  return Column(
                    children: participants.map((participant) {
                      final username = participant['username'] ?? '';
                      final uid = participant['uid'] ?? '';
                      final progress = participant['progress'] ?? 0;

                      final displayName =
                          username.toString().isNotEmpty ? username : uid;
                      final isMe = user != null && uid == user.uid;

                      final value = targetNumber > 0
                          ? (progress / targetNumber).clamp(0.0, 1.0)
                          : 0.0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.08)
                              : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    isMe ? '$displayName (You)' : displayName,
                                    style: TextStyle(
                                      fontWeight: isMe
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$progress / $targetNumber',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(value: value),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}