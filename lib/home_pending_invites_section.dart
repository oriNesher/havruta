import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/firestore_service.dart';

class HomePendingInvitesSection extends StatelessWidget {
  final String uid;
  final _firestoreService = FirestoreService();

  HomePendingInvitesSection({super.key, required this.uid});

  Future<void> _showAcceptInviteDialog({
    required BuildContext outerContext,
    required String inviteId,
    required String competitionId,
    required String competitionTitle,
  }) async {
    final goalTitleController = TextEditingController();
    final targetValueController = TextEditingController();
    final unitController = TextEditingController();
    bool isSubmitting = false;

    await showDialog(
      context: outerContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogInnerContext, setDialogState) {
            Future<void> submit() async {
              final goalTitle = goalTitleController.text.trim();
              final targetValueText = targetValueController.text.trim();
              final unit = unitController.text.trim();

              if (goalTitle.isEmpty || targetValueText.isEmpty || unit.isEmpty) {
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
                final username = await _firestoreService.getMyUsername(uid);

                if (username == null || username.trim().isEmpty) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Could not find your username')),
                  );
                  return;
                }

                await _firestoreService.acceptCompetitionInvite(
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
                      child: Text('Define your personal goal for this competition'),
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
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestoreService.getPendingInvites(uid),
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
                    FutureBuilder<String?>(
                      future: _firestoreService.getUsernameByUid(fromUid),
                      builder: (context, usernameSnapshot) {
                        if (usernameSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Text('Invited by: $fromUid');
                        }
                        final inviterUsername = usernameSnapshot.data;
                        return Text(
                          'Invited by: ${inviterUsername != null && inviterUsername.isNotEmpty ? inviterUsername : fromUid}',
                        );
                      },
                    ),
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
                                await _firestoreService.declineCompetitionInvite(
                                  inviteId: inviteId,
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error declining invite: $e'),
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
    );
  }
}
