import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'create_competition_screen.dart';
import 'competition_details_screen.dart';
import 'services/firestore_service.dart';

class HomeScreen extends StatelessWidget {
  HomeScreen({super.key});

  final FirestoreService firestoreService = FirestoreService();

  Future<void> _showAcceptInviteDialog({
    required BuildContext outerContext,
    required String inviteId,
    required String competitionId,
    required String competitionTitle,
    required String uid,
  }) async {
    final goalTitleController = TextEditingController();
    final targetValueController = TextEditingController();
    final unitController = TextEditingController();

    bool isSubmitting = false;

    await showDialog(
      context: outerContext,
      barrierDismissible: !isSubmitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogInnerContext, setDialogState) {
            Future<void> submit() async {
              final goalTitle = goalTitleController.text.trim();
              final targetValueText = targetValueController.text.trim();
              final unit = unitController.text.trim();

              if (goalTitle.isEmpty ||
                  targetValueText.isEmpty ||
                  unit.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Please fill all fields')),
                );
                return;
              }

              final targetValue = int.tryParse(targetValueText);
              if (targetValue == null || targetValue <= 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Target value must be a positive number'),
                  ),
                );
                return;
              }

              bool acceptedSuccessfully = false;

              setDialogState(() {
                isSubmitting = true;
              });

              try {
                final username = await firestoreService.getMyUsername(uid);

                if (username == null || username.trim().isEmpty) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Could not find your username'),
                    ),
                  );
                  return;
                }

                await firestoreService.acceptCompetitionInvite(
                  inviteId: inviteId,
                  competitionId: competitionId,
                  uid: uid,
                  username: username,
                  goalTitle: goalTitle,
                  targetValue: targetValue,
                  unit: unit,
                );

                acceptedSuccessfully = true;

                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();

                ScaffoldMessenger.of(outerContext).showSnackBar(
                  const SnackBar(content: Text('Invite accepted')),
                );
              } catch (e) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('Error accepting invite: $e')),
                );
              } finally {
                if (!acceptedSuccessfully && dialogContext.mounted) {
                  setDialogState(() {
                    isSubmitting = false;
                  });
                }
              }
            }

            return AlertDialog(
              title: Text('Join "$competitionTitle"'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Define your personal goal for this competition',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: goalTitleController,
                      enabled: !isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'My goal',
                        hintText: 'Get fitter / Study more / Read more',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: targetValueController,
                      enabled: !isSubmitting,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'My target value',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: unitController,
                      enabled: !isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'My unit',
                        hintText: 'pushups / minutes / pages / km',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : submit,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Accept'),
                ),
              ],
            );
          },
        );
      },
    );

    goalTitleController.dispose();
    targetValueController.dispose();
    unitController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('No logged in user')));
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
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firestoreService.getPendingInvites(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  debugPrint('Pending invites error: ${snapshot.error}');
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
                                      await _showAcceptInviteDialog(
                                        outerContext: context,
                                        inviteId: inviteId,
                                        competitionId: competitionId,
                                        competitionTitle: competitionTitle,
                                        uid: user.uid,
                                      );
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
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firestoreService.getUserCompetitions(user.uid),
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
                              Text('Type: asymmetric'),
                              const SizedBox(height: 4),
                              Text('Status: $status'),
                              const SizedBox(height: 16),
                              const Text(
                                'Participants',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 10),
                              StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>
                              >(
                                stream: firestoreService
                                    .getCompetitionParticipants(competitionId),
                                builder: (context, participantsSnapshot) {
                                  if (participantsSnapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }

                                  if (participantsSnapshot.hasError) {
                                    debugPrint('Participants stream error: ${participantsSnapshot.error}');
                                    return Text(
                                      'Error: ${participantsSnapshot.error}',
                                    );
                                  }

                                  final participantDocs =
                                      participantsSnapshot.data?.docs ?? [];

                                  if (participantDocs.isEmpty) {
                                    return const Text('No participants yet');
                                  }

                                  final participants = participantDocs
                                      .map((doc) => doc.data())
                                      .toList();

                                  participants.sort((a, b) {
                                    final progressA = a['progress'] ?? 0;
                                    final progressB = b['progress'] ?? 0;
                                    final targetA = a['targetValue'] ?? 0;
                                    final targetB = b['targetValue'] ?? 0;

                                    final percentA = targetA > 0
                                        ? progressA / targetA
                                        : 0.0;
                                    final percentB = targetB > 0
                                        ? progressB / targetB
                                        : 0.0;

                                    return percentB.compareTo(percentA);
                                  });

                                  return Column(
                                    children: participants.map((participant) {
                                      final username =
                                          participant['username'] ?? '';
                                      final uid = participant['uid'] ?? '';
                                      final progress =
                                          participant['progress'] ?? 0;
                                      final targetValue =
                                          participant['targetValue'] ?? 0;
                                      final goalTitle =
                                          participant['goalTitle'] ?? '';
                                      final unit = participant['unit'] ?? '';

                                      final name =
                                          username.toString().isNotEmpty
                                          ? username
                                          : uid;

                                      final isMe = uid == user.uid;

                                      final progressValue = targetValue > 0
                                          ? (progress / targetValue)
                                          : 0.0;

                                      final progressBarValue = progressValue
                                          .clamp(0.0, 1.0);

                                      final percentText = targetValue > 0
                                          ? '${(progressValue * 100).toStringAsFixed(0)}%'
                                          : '0%';

                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isMe
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withValues(alpha: 0.08)
                                              : Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    isMe ? '$name (You)' : name,
                                                    style: TextStyle(
                                                      fontWeight: isMe
                                                          ? FontWeight.bold
                                                          : FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  percentText,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (goalTitle
                                                .toString()
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Text(goalTitle),
                                            ],
                                            const SizedBox(height: 6),
                                            Text(
                                              '$progress / $targetValue ${unit.toString()}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            if (isMe) ...[
                                              const SizedBox(height: 8),
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: IconButton(
                                                  onPressed: () async {
                                                    try {
                                                      await firestoreService
                                                          .incrementMyProgress(
                                                            competitionId:
                                                                competitionId,
                                                            uid: user.uid,
                                                          );
                                                    } catch (e) {
                                                      if (!context.mounted) {
                                                        return;
                                                      }
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Error updating progress: $e',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  icon: const Icon(
                                                    Icons.add_circle,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 4),
                                            LinearProgressIndicator(
                                              value: progressBarValue,
                                            ),
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
