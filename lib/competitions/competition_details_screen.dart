import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../app_theme.dart';
import '../services/firestore_service.dart';
import 'challenge.dart';
import 'challenge_standings.dart';
import 'competition_invite_section.dart';
import 'widgets/challenge_activity_graph.dart';
import 'widgets/invite_link_card.dart';

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime date) =>
    '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';

/// 1-based challenge day number of [dayKey] (YYYY-MM-DD), counting from
/// [challenge]'s first day.
int? _dayNumber(Challenge challenge, String dayKey) {
  final startsAt = challenge.startsAt;
  if (startsAt == null) return null;
  final start = DateTime.parse(challenge.dayKey(startsAt));
  final day = DateTime.tryParse(dayKey);
  if (day == null) return null;
  return day.difference(start).inDays + 1;
}

class CompetitionDetailsScreen extends StatefulWidget {
  /// The challenge as the opener last saw it — shown immediately, then
  /// replaced by the live document.
  final Challenge challenge;

  const CompetitionDetailsScreen({super.key, required this.challenge});

  @override
  State<CompetitionDetailsScreen> createState() =>
      _CompetitionDetailsScreenState();
}

class _CompetitionDetailsScreenState extends State<CompetitionDetailsScreen> {
  final FirestoreService firestoreService = FirestoreService();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _challengeStream =
      firestoreService.getCompetitionDoc(widget.challenge.id);
  bool _isDeleting = false;

  String _formatLastUpdate(Timestamp? updatedAt) {
    if (updatedAt == null) return '';

    final date = updatedAt.toDate();
    final diff = DateTime.now().difference(date);

    if (diff.inSeconds < 60) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    if (diff.inDays < 7) return 'Updated ${diff.inDays}d ago';

    return 'Updated ${_monthNames[date.month - 1]} ${date.day}';
  }

  Future<void> _showEditProgressDialog({
    required Challenge challenge,
    required String uid,
    required int currentProgress,
    required int todayProgress,
    required String unit,
  }) async {
    // Last One Standing has already judged past days, so only today's
    // progress can be taken back there; elsewhere any amount can.
    final judgesDays = challenge.winCondition == WinCondition.lastStanding;
    final maxReduction = judgesDays
        ? todayProgress.clamp(0, currentProgress)
        : currentProgress;
    final minProgress = currentProgress - maxReduction;
    final unitSuffix = unit.isNotEmpty ? ' $unit' : '';

    if (maxReduction <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only progress logged today can be taken back'),
        ),
      );
      return;
    }

    final controller = TextEditingController(text: currentProgress.toString());

    final newValue = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit your progress'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    judgesDays
                        ? 'You can only take back today\'s progress '
                              '(down to $minProgress$unitSuffix)'
                        : 'You can only reduce your progress '
                              '(max: $currentProgress$unitSuffix)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'New progress',
                      suffixText: unit.isNotEmpty ? unit : null,
                      errorText: errorText,
                    ),
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      setDialogState(() {
                        if (parsed == null) {
                          errorText = 'Enter a valid number';
                        } else if (parsed < minProgress) {
                          errorText = minProgress == 0
                              ? 'Cannot be negative'
                              : 'Cannot go below $minProgress';
                        } else if (parsed > currentProgress) {
                          errorText =
                              'Cannot exceed current progress ($currentProgress)';
                        } else {
                          errorText = null;
                        }
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: errorText != null
                      ? null
                      : () {
                          final value = int.tryParse(controller.text);
                          Navigator.of(dialogContext).pop(value);
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    // not disposed: dialog exit animation keeps the TextField mounted past showDialog's return
    if (newValue == null || !mounted) return;

    final reduction = currentProgress - newValue;
    try {
      await firestoreService.updateProgress(
        competitionId: challenge.id,
        uid: uid,
        progress: newValue,
        dayKey: challenge.dayKey(DateTime.now()),
        todayReduction: math.max(0, math.min(reduction, todayProgress)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update progress: $e')),
      );
    }
  }

  Future<void> _confirmAndDeleteCompetition() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Challenge'),
          content: const Text(
            'Are you sure you want to delete this challenge? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      await firestoreService.deleteCompetition(widget.challenge.id);

      if (!mounted) return;

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Challenge deleted')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isDeleting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  /// Whether new people can still join: not once it's over, and not once a
  /// Last One Standing challenge is past day 1 (everyone must be judged
  /// from day 1). Mirrors joinClosedReason in functions/src/challenges/
  /// joining.ts.
  bool _acceptsJoins(Challenge challenge) {
    if (!challenge.isActive) return false;
    final now = DateTime.now();
    final endsAt = challenge.endsAt;
    if (endsAt != null && !now.isBefore(endsAt)) return false;
    final startsAt = challenge.startsAt;
    if (challenge.winCondition == WinCondition.lastStanding &&
        startsAt != null &&
        challenge.dayKey(now).compareTo(challenge.dayKey(startsAt)) > 0) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _challengeStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final challenge = data != null
            ? Challenge.fromDoc(widget.challenge.id, data)
            : widget.challenge;
        return _buildScreen(context, challenge);
      },
    );
  }

  Widget _buildScreen(BuildContext context, Challenge challenge) {
    final user = FirebaseAuth.instance.currentUser;
    final isCreator = user != null && user.uid == challenge.createdBy;
    final theme = Theme.of(context);
    final startsAt = challenge.startsAt;
    final endsAt = challenge.endsAt;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Challenge Details'),
        actions: [
          if (isCreator)
            IconButton(
              onPressed: _isDeleting ? null : _confirmAndDeleteCompetition,
              icon: _isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              tooltip: 'Delete Challenge',
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                challenge.title,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),

              // Mode badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  challenge.modeLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (challenge.isCompleted) ...[
                _ResultsBanner(
                  winnerUids: challenge.winnerUids,
                  firestoreService: firestoreService,
                ),
                const SizedBox(height: 20),
              ],

              // Goal — legacy personal challenges show each participant's
              // own goal on their row instead.
              if (!challenge.isLegacyPersonal &&
                  challenge.goalTitle.isNotEmpty) ...[
                Text('Goal', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(challenge.goalSummary),
                const SizedBox(height: 6),
                Text(
                  challenge.winCondition.tagline,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              if (challenge.winCondition == WinCondition.lastStanding &&
                  startsAt != null) ...[
                Text('Day 1', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(_formatDate(startsAt)),
                const SizedBox(height: 20),
              ],

              // End date, or the free-text deadline of older challenges.
              if (endsAt != null) ...[
                Text('Ends', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  'After ${_formatDate(endsAt.subtract(const Duration(days: 1)))}',
                ),
                const SizedBox(height: 20),
              ] else if (challenge.legacyDeadline?.isNotEmpty == true) ...[
                Text('Deadline', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(challenge.legacyDeadline!),
                const SizedBox(height: 20),
              ],

              // Rules & Notes
              if (challenge.description.isNotEmpty) ...[
                Text(
                  'Rules & Notes',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(challenge.description),
                const SizedBox(height: 20),
              ],

              Text('Status', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(challenge.status.isNotEmpty
                  ? '${challenge.status[0].toUpperCase()}${challenge.status.substring(1)}'
                  : challenge.status),
              const SizedBox(height: 20),

              Text(
                'Started by',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              FutureBuilder<String?>(
                future: firestoreService.getUsernameByUid(challenge.createdBy),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text('Loading...');
                  }
                  if (snapshot.hasError) {
                    return Text(challenge.createdBy);
                  }
                  final username = snapshot.data;
                  return Text(
                    username != null && username.isNotEmpty
                        ? username
                        : challenge.createdBy,
                  );
                },
              ),
              const SizedBox(height: 32),

              if (isCreator) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isDeleting ? null : _confirmAndDeleteCompetition,
                    icon: _isDeleting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                    label: Text(
                      _isDeleting ? 'Deleting...' : 'Delete Challenge',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              if (user != null && _acceptsJoins(challenge)) ...[
                InviteLinkCard(
                  competitionId: challenge.id,
                  competitionTitle: challenge.title,
                ),
                const SizedBox(height: 16),
                CompetitionInviteSection(
                  challenge: challenge,
                  currentUserUid: user.uid,
                ),
                const SizedBox(height: 32),
              ],

              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: firestoreService.getCompetitionParticipants(
                  challenge.id,
                ),
                builder: (context, snapshot) {
                  final participantsHeading = [
                    Text(
                      'Participants',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                  ];

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...participantsHeading,
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ],
                    );
                  }

                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...participantsHeading,
                        Text('Error: ${snapshot.error}'),
                      ],
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...participantsHeading,
                        const Text('No participants yet'),
                      ],
                    );
                  }

                  final participants = rankParticipants(
                    challenge,
                    docs.map((doc) => doc.data()),
                  );
                  final todayKey = challenge.dayKey(DateTime.now());
                  final leaderProgress = participants
                      .map((p) => (p['progress'] as num? ?? 0).toInt())
                      .fold<int>(0, (a, b) => a > b ? a : b);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ChallengeActivityGraph(
                        competitionId: challenge.id,
                        participants: participants,
                        currentUserUid: user?.uid,
                      ),
                      const SizedBox(height: 28),
                      ...participantsHeading,
                      ...participants.map((participant) {
                        final uid = participant['uid'] as String? ?? '';
                        final isMe = user != null && uid == user.uid;
                        final progress =
                            (participant['progress'] as num? ?? 0).toInt();
                        final todayProgress =
                            ((participant['dailyProgress']
                                        as Map<String, dynamic>?)?[todayKey]
                                    as num? ??
                                0)
                            .toInt();
                        final eliminated =
                            participant['eliminatedOnDay'] != null;
                        final canEdit = isMe &&
                            challenge.isActive &&
                            !eliminated &&
                            progress > 0;

                        return _ParticipantCard(
                          challenge: challenge,
                          participant: participant,
                          isMe: isMe,
                          todayProgress: todayProgress,
                          leaderProgress: leaderProgress,
                          lastUpdateText: _formatLastUpdate(
                            participant['updatedAt'] as Timestamp?,
                          ),
                          onEdit: canEdit
                              ? () => _showEditProgressDialog(
                                  challenge: challenge,
                                  uid: user.uid,
                                  currentProgress: progress,
                                  todayProgress: todayProgress,
                                  unit: (participant['unit'] ?? '').toString(),
                                )
                              : null,
                        );
                      }),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Final results
// ─────────────────────────────────────────────

class _ResultsBanner extends StatelessWidget {
  final List<String> winnerUids;
  final FirestoreService firestoreService;

  const _ResultsBanner({
    required this.winnerUids,
    required this.firestoreService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.emoji_events_outlined,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: winnerUids.isEmpty
                ? Text(
                    'Challenge over — no winner this time.',
                    style: AppTheme.display(
                      color: theme.colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : FutureBuilder<List<String?>>(
                    future: Future.wait(
                      winnerUids.map(firestoreService.getUsernameByUid),
                    ),
                    builder: (context, snapshot) {
                      final names = [
                        for (final (i, name)
                            in (snapshot.data ?? const []).indexed)
                          name?.isNotEmpty == true ? name! : winnerUids[i],
                      ];
                      final who = names.isEmpty ? '…' : names.join(' & ');
                      return Text(
                        winnerUids.length > 1
                            ? 'Challenge over — $who share the win!'
                            : 'Challenge over — $who won!',
                        style: AppTheme.display(
                          color: theme.colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Participant row, per win condition
// ─────────────────────────────────────────────

class _ParticipantCard extends StatelessWidget {
  final Challenge challenge;
  final Map<String, dynamic> participant;
  final bool isMe;
  final int todayProgress;
  final int leaderProgress;
  final String lastUpdateText;
  final VoidCallback? onEdit;

  const _ParticipantCard({
    required this.challenge,
    required this.participant,
    required this.isMe,
    required this.todayProgress,
    required this.leaderProgress,
    required this.lastUpdateText,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = participant['uid'] as String? ?? '';
    final username = (participant['username'] ?? '').toString();
    final displayName = username.isNotEmpty ? username : uid;
    final progress = (participant['progress'] as num? ?? 0).toInt();
    final unit = (participant['unit'] ?? '').toString();
    final unitSuffix = unit.isNotEmpty ? ' $unit' : '';
    final goalTitle = (participant['goalTitle'] ?? '').toString();
    final linkedGoalTitle = participant['linkedGoalTitle'] as String?;
    final eliminatedOnDay = participant['eliminatedOnDay'] as String?;
    final mutedColor = theme.colorScheme.onSurface.withValues(alpha: 0.45);

    final (trailing, detail, barValue) = _modeStats(
      theme: theme,
      progress: progress,
      unitSuffix: unitSuffix,
      eliminatedOnDay: eliminatedOnDay,
    );

    return Opacity(
      opacity: eliminatedOnDay != null ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isMe ? '$displayName (You)' : displayName,
                    style: TextStyle(
                      fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
                trailing,
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Edit progress',
                    onPressed: onEdit,
                  ),
              ],
            ),
            // Legacy personal goal challenges: each participant's own goal.
            if (challenge.isLegacyPersonal && goalTitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(goalTitle),
            ],
            if (linkedGoalTitle != null && linkedGoalTitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.arrow_outward, size: 12, color: mutedColor),
                  const SizedBox(width: 4),
                  Text(
                    'Connected to: $linkedGoalTitle',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: mutedColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Text(
              detail,
              style: AppTheme.mono(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: barValue),
            if (lastUpdateText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                lastUpdateText,
                style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The row's trailing stat, detail line and bar fill for this mode.
  (Widget, String, double) _modeStats({
    required ThemeData theme,
    required int progress,
    required String unitSuffix,
    required String? eliminatedOnDay,
  }) {
    final stat = AppTheme.mono(fontWeight: FontWeight.w600);

    switch (challenge.winCondition) {
      case WinCondition.firstToTarget:
        final target = challenge.targetFor(participant) ?? 0;
        final ratio = target > 0 ? progress / target : 0.0;
        return (
          Text('${(ratio * 100).toStringAsFixed(0)}%', style: stat),
          unitSuffix.isNotEmpty
              ? '$progress / $target$unitSuffix'
              : '$progress / $target completed',
          ratio.clamp(0.0, 1.0),
        );
      case WinCondition.mostProgress:
        return (
          Text('$progress$unitSuffix', style: stat),
          'Total: $progress$unitSuffix',
          leaderProgress > 0 ? progress / leaderProgress : 0.0,
        );
      case WinCondition.lastStanding:
        final minimum = challenge.rules.dailyMinimum ?? 0;
        if (eliminatedOnDay != null) {
          final day = _dayNumber(challenge, eliminatedOnDay);
          return (
            _StatusChip(label: 'Out', color: theme.colorScheme.error),
            day != null
                ? 'Missed day $day · total $progress$unitSuffix'
                : 'Out · total $progress$unitSuffix',
            0.0,
          );
        }
        final startsAt = challenge.startsAt;
        if (startsAt != null && DateTime.now().isBefore(startsAt)) {
          return (
            _StatusChip(label: 'In', color: theme.colorScheme.primary),
            'Starts ${_formatDate(startsAt)}',
            0.0,
          );
        }
        final safe = minimum > 0 && todayProgress >= minimum;
        return (
          _StatusChip(
            label: safe ? 'Safe today' : 'In',
            color: safe ? theme.colorScheme.tertiary : theme.colorScheme.primary,
          ),
          'Today: $todayProgress / $minimum$unitSuffix',
          minimum > 0 ? (todayProgress / minimum).clamp(0.0, 1.0) : 0.0,
        );
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: AppTheme.display(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
