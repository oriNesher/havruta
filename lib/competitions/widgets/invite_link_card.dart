import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/invite_service.dart';
import '../../tips/feature_tip.dart';
import '../../tips/feature_tip_anchor.dart';

/// Shareable-link invite card. Used both right after a challenge is created
/// and later from the challenge details screen, so anyone can pull up a
/// fresh invite link at any point, not just at creation time.
class InviteLinkCard extends StatefulWidget {
  final String competitionId;
  final String competitionTitle;

  /// Fetches the link as soon as the card mounts, instead of on the first
  /// tap, so Share opens the sheet with no round trip in between. Only set
  /// where sharing is the point of the screen (ChallengeInviteScreen) —
  /// createInvite mints a real, 30-day bearer link on a cache miss, so
  /// somewhere the card is just one section among many (challenge details)
  /// shouldn't create one for a participant who was only passing through.
  final bool prewarm;

  const InviteLinkCard({
    super.key,
    required this.competitionId,
    required this.competitionTitle,
    this.prewarm = false,
  });

  @override
  State<InviteLinkCard> createState() => _InviteLinkCardState();
}

class _InviteLinkCardState extends State<InviteLinkCard> {
  final _inviteService = InviteService();
  bool _isCreatingLink = false;

  // Held for the card's lifetime so a second action (share, then copy)
  // doesn't pay for the callable again. createInvite already returns the
  // same link for repeat calls, so this only removes the wait, never
  // changes which link is handed out.
  Future<({String linkId, String url})>? _invite;

  @override
  void initState() {
    super.initState();
    if (widget.prewarm) _prewarm();
  }

  Future<void> _prewarm() async {
    try {
      await _resolveInvite();
    } catch (_) {
      // Nothing is on screen to report this to yet, and the first tap
      // retries properly — but the rejection still has to be caught here
      // or it surfaces as an uncaught exception in the zone.
      _invite = null;
    }
  }

  Future<({String linkId, String url})> _resolveInvite() {
    final pending = _invite ??=
        _inviteService.createInvite(competitionId: widget.competitionId);
    return pending;
  }

  Future<void> _shareLink() async {
    setState(() => _isCreatingLink = true);
    try {
      final invite = await _resolveInvite();

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          text: invite.url,
          subject: 'Join me in "${widget.competitionTitle}" on Havruta',
        ),
      );
    } catch (e) {
      // Drop the cached failure so the next tap genuinely retries rather
      // than replaying the same rejected future forever.
      _invite = null;
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
      final invite = await _resolveInvite();
      await Clipboard.setData(ClipboardData(text: invite.url));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite link copied')));
    } catch (e) {
      _invite = null;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create invite link: $e')));
    } finally {
      if (mounted) setState(() => _isCreatingLink = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FeatureTipAnchor(
      tip: FeatureTip.inviteLink,
      child: Card(
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
    );
  }
}
