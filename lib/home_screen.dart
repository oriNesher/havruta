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
    final firebaseService = FirestoreService();

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
      body: Padding(
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
              'My Competitions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: firebaseService.getUserCompetitions(user.uid),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Error: ${snapshot.error}'),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return const Center(
                      child: Text('No competitions yet'),
                    );
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final competition = doc.data();

                      final competitionId = doc.id;
                      final title = competition['title'] ?? '';
                      final description = competition['description'] ?? '';
                      final targetNumber = competition['targetNumber'] ?? 0;
                      final unit = competition['unit'] ?? '';
                      final status = competition['status'] ?? '';
                      final createdBy = competition['createdBy'] ?? '';

                      return StreamBuilder<
                          DocumentSnapshot<Map<String, dynamic>>>(
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
                                              await firebaseService
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
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}