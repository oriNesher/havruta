import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'create_competition_screen.dart';
import 'competition_details_screen.dart';
import 'services/firestore_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final firestoreService = FirestoreService();

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text('No logged in user'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Havruta'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hello ${user.email ?? ""}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateCompetitionScreen(),
                    ),
                  );
                },
                child: const Text('Create Competition'),
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Pending Invites',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firestoreService.getPendingInvites(user.uid),
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
                  return const Text('No pending invites');
                }

                return Column(
                  children: docs.map((doc) {
                    final invite = doc.data();

                    final inviteId = doc.id;
                    final competitionId = invite['competitionId'] ?? '';
                    final competitionTitle = invite['competitionTitle'] ?? '';
                    final fromUid = invite['fromUid'] ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              competitionTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('Invited by: $fromUid'),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      try {
                                        final username =
                                            await firestoreService.getMyUsername(
                                          user.uid,
                                        );

                                        if (username == null ||
                                            username.trim().isEmpty) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Could not find your username',
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        await firestoreService
                                            .acceptCompetitionInvite(
                                          inviteId: inviteId,
                                          competitionId: competitionId,
                                          uid: user.uid,
                                          username: username,
                                        );
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Error accepting invite: $e',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: const Text('Accept'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      try {
                                        await firestoreService
                                            .declineCompetitionInvite(
                                          inviteId: inviteId,
                                        );
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Error declining invite: $e',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: const Text('Decline'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 24),

            const Text(
              'My Competitions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firestoreService.getUserCompetitions(user.uid),
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
                  return const Text('No competitions yet');
                }

                return Column(
                  children: docs.map((doc) {
                    final competition = doc.data();

                    final competitionId = doc.id;
                    final title = competition['title'] ?? '';
                    final description = competition['description'] ?? '';
                    final targetNumber = competition['targetNumber'] ?? 0;
                    final unit = competition['unit'] ?? '';
                    final status = competition['status'] ?? '';
                    final createdBy = competition['createdBy'] ?? '';

                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('competitions')
                          .doc(competitionId)
                          .collection('participants')
                          .doc(user.uid)
                          .snapshots(),
                      builder: (context, participantSnapshot) {
                        final participantData = participantSnapshot.data?.data();
                        final myProgress = participantData?['progress'] ?? 0;

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
                                  targetNumber: targetNumber,
                                  unit: unit,
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
                                  Text('Target: $targetNumber $unit'),
                                  const SizedBox(height: 4),
                                  Text('Status: $status'),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'My progress: $myProgress / $targetNumber',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () async {
                                          try {
                                            await firestoreService
                                                .incrementMyProgress(
                                              competitionId: competitionId,
                                              uid: user.uid,
                                            );
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Error updating progress: $e',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        icon: const Icon(Icons.add_circle),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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