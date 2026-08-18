import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/invite_service.dart';

/// Shareable-link invite card. Used both right after a challenge is created
/// and later from the challenge details screen, so anyone can pull up a
/// fresh invite link at any point, not just at creation time.
class InviteLinkCard extends StatefulWidget {
  final String competitionId;
  final String competitionTitle;

  const InviteLinkCard({
    super.key,
    required this.competitionId,
    required this.competitionTitle,
  });

  @override
  State<InviteLinkCard> createState() => _InviteLinkCardState();
}

class _InviteLinkCardState extends State<InviteLinkCard> {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
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
    );
  }
}
