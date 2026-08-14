import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../app_theme.dart';
import '../services/firestore_service.dart';

class HomePendingInvitesSection extends StatelessWidget {
  final String uid;
  final _firestoreService = FirestoreService();

  HomePendingInvitesSection({super.key, required this.uid});

  // ── Personal Goal accept dialog ────────────────────────────────────────────

  Future<void> _showPersonalGoalAcceptDialog({
    required BuildContext outerContext,
    required String inviteId,
    required String competitionId,
    required String competitionTitle,
    String? creatorGoalTitle,
    int? creatorTargetValue,
    String? creatorUnit,
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
                    const SnackBar(
                      content: Text('Could not find your username'),
                    ),
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

            final hasCreatorGoal = creatorGoalTitle != null &&
                creatorGoalTitle.isNotEmpty &&
                creatorTargetValue != null;
            final creatorGoalDisplay = hasCreatorGoal
                ? (creatorUnit != null && creatorUnit.isNotEmpty
                    ? '$creatorGoalTitle — $creatorTargetValue $creatorUnit'
                    : '$creatorGoalTitle — $creatorTargetValue')
                : null;

            return AlertDialog(
              title: Text('Join "$competitionTitle"'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (creatorGoalDisplay != null) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Creator's goal, for reference:",
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          creatorGoalDisplay,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
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

  // ── Shared Goal accept dialog ──────────────────────────────────────────────

  Future<void> _showSharedGoalAcceptDialog({
    required BuildContext outerContext,
    required String inviteId,
    required String competitionId,
    required String competitionTitle,
    required String sharedGoalTitle,
    required int sharedTargetValue,
    required String sharedUnit,
  }) async {
    bool isSubmitting = false;

    await showDialog(
      context: outerContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            Future<void> submit() async {
              bool acceptedSuccessfully = false;

              setDialogState(() {
                isSubmitting = true;
              });

              try {
                final username = await _firestoreService.getMyUsername(uid);

                if (username == null || username.trim().isEmpty) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Could not find your username'),
                    ),
                  );
                  return;
                }

                await _firestoreService.acceptSharedGoalCompetitionInvite(
                  inviteId: inviteId,
                  competitionId: competitionId,
                  uid: uid,
                  username: username,
                  sharedGoalTitle: sharedGoalTitle,
                  sharedTargetValue: sharedTargetValue,
                  sharedUnit: sharedUnit,
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

            final goalDisplay = sharedUnit.isNotEmpty
                ? '$sharedGoalTitle — $sharedTargetValue $sharedUnit'
                : '$sharedGoalTitle — $sharedTargetValue';

            return AlertDialog(
              title: Text('Join "$competitionTitle"'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('This is a Shared Goal Challenge.'),
                  const SizedBox(height: 4),
                  const Text(
                    'Everyone works toward the same goal:',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        dialogContext,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      goalDisplay,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "You'll each log your own progress toward this shared target.",
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
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
                      : const Text('Join'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
            final competitionType =
                invite['competitionType'] as String? ?? 'personalGoalChallenge';
            final isShared = competitionType == 'sharedGoalChallenge';

            final sharedGoalTitle =
                invite['sharedGoalTitle'] as String? ?? '';
            final sharedTargetValue =
                (invite['sharedTargetValue'] as num?)?.toInt() ?? 0;
            final sharedUnit = invite['sharedUnit'] as String? ?? '';

            final creatorGoalTitle = invite['creatorGoalTitle'] as String?;
            final creatorTargetValue =
                (invite['creatorTargetValue'] as num?)?.toInt();
            final creatorUnit = invite['creatorUnit'] as String?;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      competitionTitle,
                      style: AppTheme.display(
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Challenge type badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isShared
                            ? 'Shared Goal Challenge'
                            : 'Personal Goal Challenge',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    // Shared goal preview
                    if (isShared && sharedGoalTitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        sharedUnit.isNotEmpty
                            ? 'Goal: $sharedGoalTitle — $sharedTargetValue $sharedUnit'
                            : 'Goal: $sharedGoalTitle — $sharedTargetValue',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
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
                              if (isShared) {
                                await _showSharedGoalAcceptDialog(
                                  outerContext: context,
                                  inviteId: inviteId,
                                  competitionId: competitionId,
                                  competitionTitle: competitionTitle,
                                  sharedGoalTitle: sharedGoalTitle,
                                  sharedTargetValue: sharedTargetValue,
                                  sharedUnit: sharedUnit,
                                );
                              } else {
                                await _showPersonalGoalAcceptDialog(
                                  outerContext: context,
                                  inviteId: inviteId,
                                  competitionId: competitionId,
                                  competitionTitle: competitionTitle,
                                  creatorGoalTitle: creatorGoalTitle,
                                  creatorTargetValue: creatorTargetValue,
                                  creatorUnit: creatorUnit,
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
