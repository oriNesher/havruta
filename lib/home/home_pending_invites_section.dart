import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../app_theme.dart';
import '../competitions/challenge.dart';
import '../services/firestore_service.dart';
import '../services/invite_service.dart';
import '../competitions/widgets/personal_goal_input_dialog.dart';

class HomePendingInvitesSection extends StatelessWidget {
  final String uid;
  final _firestoreService = FirestoreService();
  final _inviteService = InviteService();

  HomePendingInvitesSection({super.key, required this.uid});

  // ── Legacy Personal Goal accept dialog ─────────────────────────────────────
  // Only for invites sent before win conditions; remove once answered.

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
      onSubmit: (goalTitle, targetValue) async {
        await _inviteService.acceptInvite(
          inviteId: inviteId,
          goalTitle: goalTitle,
          targetValue: targetValue,
        );
      },
    );

    if (joined && outerContext.mounted) {
      ScaffoldMessenger.of(
        outerContext,
      ).showSnackBar(const SnackBar(content: Text('Invite accepted')));
    }
  }

  // ── Challenge accept dialog ────────────────────────────────────────────────

  Future<void> _showChallengeAcceptDialog({
    required BuildContext outerContext,
    required String inviteId,
    required Challenge challenge,
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
                // The server checks the invite and copies the challenge's
                // goal onto the new participant.
                await _inviteService.acceptInvite(inviteId: inviteId);

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
              title: Text('Join "${challenge.title}"'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This is a ${challenge.winCondition.label} challenge.'),
                  const SizedBox(height: 4),
                  Text(challenge.winCondition.tagline),
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
                      challenge.goalSummary,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "You'll each log your own progress toward this shared goal.",
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
            // An invite carries the challenge's definition (see
            // sendCompetitionInvite), so it reads like the challenge itself.
            final challenge = Challenge.fromDoc(competitionId, {
              ...invite,
              'title': competitionTitle,
              'type': invite['competitionType'],
            });

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
                        challenge.modeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    // Shared goal preview
                    if (!challenge.isLegacyPersonal &&
                        challenge.goalTitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Goal: ${challenge.goalSummary}',
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
                                if (!challenge.isLegacyPersonal) {
                                  await _showChallengeAcceptDialog(
                                    outerContext: context,
                                    inviteId: inviteId,
                                    challenge: challenge,
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
