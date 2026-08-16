import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../app_theme.dart';
import '../services/firestore_service.dart';
import '../competitions/widgets/personal_goal_input_dialog.dart';

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
    final joined = await showPersonalGoalInputDialog(
      context: outerContext,
      competitionTitle: competitionTitle,
      creatorGoalTitle: creatorGoalTitle,
      creatorTargetValue: creatorTargetValue,
      creatorUnit: creatorUnit,
      submitLabel: 'Accept',
      onSubmit: (goalTitle, targetValue, unit) async {
        final username = await _firestoreService.getMyUsername(uid);
        if (username == null || username.trim().isEmpty) {
          throw Exception('Could not find your username');
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
      },
    );

    if (joined && outerContext.mounted) {
      ScaffoldMessenger.of(
        outerContext,
      ).showSnackBar(const SnackBar(content: Text('Invite accepted')));
    }
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
