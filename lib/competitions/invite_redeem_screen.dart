import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import '../services/invite_service.dart';
import 'challenge.dart';
import 'competition_details_screen.dart';
import 'widgets/personal_goal_input_dialog.dart';

/// Shown when the app opens an invite link (or resumes one saved before
/// login/registration/install). Recipient-facing counterpart to
/// ChallengeInviteScreen: shows who invited them and to what challenge,
/// then lets them join.
class InviteRedeemScreen extends StatefulWidget {
  final String linkId;

  /// AuthGate renders this screen inline (in place of HomeScreen) rather
  /// than pushing it as a route, so there's nothing to Navigator.pop back
  /// to. onDone tells AuthGate to stop showing it — called on dismiss, and
  /// right before navigating into the joined challenge (so backing out of
  /// that screen lands on Home, not back on this invite).
  final VoidCallback onDone;

  const InviteRedeemScreen({
    super.key,
    required this.linkId,
    required this.onDone,
  });

  @override
  State<InviteRedeemScreen> createState() => _InviteRedeemScreenState();
}

class _InviteRedeemScreenState extends State<InviteRedeemScreen> {
  final _inviteService = InviteService();
  final _firestoreService = FirestoreService();

  bool _isLoading = true;
  bool _isJoining = false;
  InvitePreview? _preview;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final preview = await _inviteService.getInvite(linkId: widget.linkId);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _isLoading = false;
      });
    }
  }

  void _dismiss() {
    widget.onDone();
  }

  Future<void> _openCompetitionDetails(String competitionId) async {
    final doc = await _firestoreService.getCompetition(competitionId);
    final data = doc.data();
    if (!mounted) return;

    // Flip AuthGate back to HomeScreen first, so backing out of the details
    // screen below lands on Home rather than re-showing this invite.
    widget.onDone();

    if (data == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompetitionDetailsScreen(
          challenge: Challenge.fromDoc(competitionId, data),
        ),
      ),
    );
  }

  Future<void> _joinShared(InvitePreview preview) async {
    setState(() => _isJoining = true);
    try {
      final result = await _inviteService.redeemInvite(linkId: widget.linkId);
      if (!mounted) return;
      await _openCompetitionDetails(result.competitionId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not join: $e')));
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _joinPersonal(InvitePreview preview) async {
    String? joinedCompetitionId;

    final joined = await showPersonalGoalInputDialog(
      context: context,
      competitionTitle: preview.competitionTitle ?? '',
      creatorGoalTitle: preview.creatorGoalTitle,
      creatorTargetValue: preview.creatorTargetValue,
      creatorUnit: preview.creatorUnit,
      submitLabel: "I'm in",
      onSubmit: (goalTitle, targetValue) async {
        final result = await _inviteService.redeemInvite(
          linkId: widget.linkId,
          goalTitle: goalTitle,
          targetValue: targetValue,
        );
        joinedCompetitionId = result.competitionId;
      },
    );

    if (joined && joinedCompetitionId != null && mounted) {
      await _openCompetitionDetails(joinedCompetitionId!);
    }
  }

  Future<void> _join() async {
    final preview = _preview;
    if (preview == null || !preview.valid) return;

    if (preview.isLegacyPersonal) {
      await _joinPersonal(preview);
    } else {
      await _joinShared(preview);
    }
  }

  String _errorMessage(String? reason) {
    switch (reason) {
      case 'revoked':
        return 'This invite link has been revoked by its creator.';
      case 'expired':
        return 'This invite link has expired.';
      case 'full':
        return 'This invite link has reached its limit.';
      default:
        return "This invite link doesn't exist or is no longer valid.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Challenge invite'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(onPressed: _dismiss, child: const Text('Not now')),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildBody(theme),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const CircularProgressIndicator();
    }

    if (_loadError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Something went wrong: $_loadError'),
          const SizedBox(height: 16),
          FilledButton(onPressed: _loadPreview, child: const Text('Retry')),
        ],
      );
    }

    final preview = _preview!;

    if (!preview.valid) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.link_off,
            size: 40,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(_errorMessage(preview.reason), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          OutlinedButton(onPressed: _dismiss, child: const Text('Go home')),
        ],
      );
    }

    final challenge = preview.challenge;
    final String? goalDisplay;
    if (challenge.isLegacyPersonal) {
      final goalTitle = preview.creatorGoalTitle;
      final unit = preview.creatorUnit;
      goalDisplay = (goalTitle != null && goalTitle.isNotEmpty)
          ? (unit != null && unit.isNotEmpty
                ? '$goalTitle — ${preview.creatorTargetValue} $unit'
                : '$goalTitle — ${preview.creatorTargetValue}')
          : null;
    } else {
      goalDisplay = challenge.goalTitle.isNotEmpty
          ? challenge.goalSummary
          : null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${preview.createdByUsername ?? 'Someone'} invited you',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          preview.competitionTitle ?? '',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(challenge.modeLabel, style: theme.textTheme.bodySmall),
        if (!challenge.isLegacyPersonal) ...[
          const SizedBox(height: 4),
          Text(
            challenge.winCondition.tagline,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
        if (goalDisplay != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              goalDisplay,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isJoining ? null : _join,
            child: _isJoining
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("I'm in"),
          ),
        ),
      ],
    );
  }
}
