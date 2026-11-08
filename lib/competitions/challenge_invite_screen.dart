import 'package:flutter/material.dart';

import 'challenge.dart';
import 'competition_invite_section.dart';
import 'widgets/challenge_creation_stepper.dart';
import 'widgets/invite_link_card.dart';

/// Dedicated invite screen shown right after a challenge is created.
/// Deliberately contains only two things: a shareable link and a search
/// field — no locked-out form fields left over from the previous screen.
class ChallengeInviteScreen extends StatelessWidget {
  final Challenge challenge;
  final String currentUserUid;

  const ChallengeInviteScreen({
    super.key,
    required this.challenge,
    required this.currentUserUid,
  });

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
              '"${challenge.title}" is ready',
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
              competitionId: challenge.id,
              competitionTitle: challenge.title,
              prewarm: true,
            ),
            const SizedBox(height: 24),

            // Secondary action: search for someone already on Havruta.
            CompetitionInviteSection(
              challenge: challenge,
              currentUserUid: currentUserUid,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    Navigator.popUntil(context, (route) => route.isFirst),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
