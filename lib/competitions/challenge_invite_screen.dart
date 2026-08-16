import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/invite_service.dart';
import 'competition_invite_section.dart';
import 'widgets/challenge_creation_stepper.dart';

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
  final _inviteService = InviteService();
  bool _isCreatingLink = false;

  Future<void> _shareLink() async {
    setState(() => _isCreatingLink = true);
    try {
      final invite = await _inviteService.createInvite(
        competitionId: widget.competitionId,
      );

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          text: invite.url,
          subject: 'Join me in "${widget.competitionTitle}" on Havruta',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create invite link: $e')));
    } finally {
      if (mounted) setState(() => _isCreatingLink = false);
    }
  }

  Future<void> _copyLink() async {
    setState(() => _isCreatingLink = true);
    try {
      final invite = await _inviteService.createInvite(
        competitionId: widget.competitionId,
      );
      await Clipboard.setData(ClipboardData(text: invite.url));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite link copied')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create invite link: $e')));
    } finally {
      if (mounted) setState(() => _isCreatingLink = false);
    }
  }

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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share invite link',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Anyone with this link can join "${widget.competitionTitle}".',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isCreatingLink ? null : _shareLink,
                            icon: _isCreatingLink
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.ios_share),
                            label: const Text('Share'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _isCreatingLink ? null : _copyLink,
                          icon: const Icon(Icons.copy_outlined),
                          tooltip: 'Copy link',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
