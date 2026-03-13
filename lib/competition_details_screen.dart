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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            if (description.isNotEmpty) ...[
              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(description),
              const SizedBox(height: 20),
            ],

            const Text(
              'Target',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text('$targetNumber $unit'),
            const SizedBox(height: 20),

            const Text(
              'Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(status),
            const SizedBox(height: 20),

            const Text(
              'Created By',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(createdBy),
            const SizedBox(height: 20),

            const Text(
              'Competition ID',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
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

            const Text(
              'Participants',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
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

                return Column(
                  children: docs.map((doc) {
                    final data = doc.data();
                    final username = data['username'] ?? '';
                    final uid = data['uid'] ?? '';
                    final progress = data['progress'] ?? 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(
                          username.toString().isNotEmpty ? username : uid,
                        ),
                        subtitle: Text('Progress: $progress / $targetNumber'),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}