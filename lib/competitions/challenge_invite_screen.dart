import 'package:flutter/material.dart';

import 'competition_invite_section.dart';
import 'widgets/challenge_creation_stepper.dart';
import 'widgets/invite_link_card.dart';

/// Dedicated invite screen shown right after a challenge is created.
/// Deliberately contains only two things: a shareable link and a search
/// field — no locked-out form fields left over from the previous screen.
class ChallengeInviteScreen extends StatefulWidget {
  final String competitionId;
  final String competitionTitle;
  final String competitionType;
  final String currentUserUid;
  final String? sharedGoalTitle;
  final int? sharedTargetValue;
  final String? sharedUnit;
  final String? creatorGoalTitle;
  final int? creatorTargetValue;
  final String? creatorUnit;

  const ChallengeInviteScreen({
    super.key,
    required this.competitionId,
    required this.competitionTitle,
    required this.competitionType,
    required this.currentUserUid,
    this.sharedGoalTitle,
    this.sharedTargetValue,
    this.sharedUnit,
    this.creatorGoalTitle,
    this.creatorTargetValue,
    this.creatorUnit,
  });

  @override
  State<ChallengeInviteScreen> createState() => _ChallengeInviteScreenState();
}

class _ChallengeInviteScreenState extends State<ChallengeInviteScreen> {
  void _finish() {
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Invite others')),
      bottomNavigationBar: const ChallengeCreationStepper(currentStep: 2),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${widget.competitionTitle}" is ready',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Invite people to do it with you.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),

            // Primary action: share invite link — lowest friction, works
            // through the OS share sheet for 1:1 chat sharing.
            InviteLinkCard(
              competitionId: widget.competitionId,
              competitionTitle: widget.competitionTitle,
            ),
            const SizedBox(height: 24),

            // Secondary action: search for someone already on Havruta.
            CompetitionInviteSection(
              competitionId: widget.competitionId,
              competitionTitle: widget.competitionTitle,
              currentUserUid: widget.currentUserUid,
              competitionType: widget.competitionType,
              sharedGoalTitle: widget.sharedGoalTitle,
              sharedTargetValue: widget.sharedTargetValue,
              sharedUnit: widget.sharedUnit,
              creatorGoalTitle: widget.creatorGoalTitle,
              creatorTargetValue: widget.creatorTargetValue,
              creatorUnit: widget.creatorUnit,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _finish,
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
