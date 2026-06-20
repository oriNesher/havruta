import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'services/firestore_service.dart';
import 'competition_invite_section.dart';

class CompetitionDetailsScreen extends StatefulWidget {
  final String competitionId;
  final String title;
  final String description;
  final String status;
  final String createdBy;
  final String? deadline;

  const CompetitionDetailsScreen({
    super.key,
    required this.competitionId,
    required this.title,
    required this.description,
    required this.status,
    required this.createdBy,
    this.deadline,
  });

  @override
  State<CompetitionDetailsScreen> createState() =>
      _CompetitionDetailsScreenState();
}

class _CompetitionDetailsScreenState extends State<CompetitionDetailsScreen> {
  final FirestoreService firestoreService = FirestoreService();
  bool _isDeleting = false;

  Future<void> _showEditProgressDialog({
    required String competitionId,
    required String uid,
    required int currentProgress,
    required int targetValue,
    required String unit,
  }) async {
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
                    unit.isNotEmpty
                        ? 'You can only reduce your progress (max: $currentProgress $unit)'
                        : 'You can only reduce your progress (max: $currentProgress)',
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
                        } else if (parsed < 0) {
                          errorText = 'Cannot be negative';
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

    try {
      await firestoreService.updateProgress(
        competitionId: competitionId,
        uid: uid,
        progress: newValue,
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
      await firestoreService.deleteCompetition(widget.competitionId);

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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isCreator = user != null && user.uid == widget.createdBy;
    final theme = Theme.of(context);

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
                widget.title,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),

              // Format badge
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
                  'Personal Goal Challenge',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Deadline (if set)
              if (widget.deadline != null &&
                  widget.deadline!.isNotEmpty) ...[
                Text(
                  'Deadline',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(widget.deadline!),
                const SizedBox(height: 20),
              ],

              // Rules & Notes (was Description)
              if (widget.description.isNotEmpty) ...[
                Text(
                  'Rules & Notes',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(widget.description),
                const SizedBox(height: 20),
              ],

              Text('Status', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(widget.status.isNotEmpty
                  ? '${widget.status[0].toUpperCase()}${widget.status.substring(1)}'
                  : widget.status),
              const SizedBox(height: 20),

              Text(
                'Started by',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              FutureBuilder<String?>(
                future: firestoreService.getUsernameByUid(widget.createdBy),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text('Loading...');
                  }
                  if (snapshot.hasError) {
                    return Text(widget.createdBy);
                  }
                  final username = snapshot.data;
                  return Text(
                    username != null && username.isNotEmpty
                        ? username
                        : widget.createdBy,
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

              if (user != null) ...[
                CompetitionInviteSection(
                  competitionId: widget.competitionId,
                  competitionTitle: widget.title,
                  currentUserUid: user.uid,
                ),
                const SizedBox(height: 32),
              ],

              Text(
                'Participants',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),

              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: firestoreService.getCompetitionParticipants(
                  widget.competitionId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return const Text('No participants yet');
                  }

                  final participants = docs.map((doc) => doc.data()).toList();

                  participants.sort((a, b) {
                    final progressA = a['progress'] ?? 0;
                    final progressB = b['progress'] ?? 0;
                    final targetA = a['targetValue'] ?? 0;
                    final targetB = b['targetValue'] ?? 0;

                    final percentA =
                        targetA > 0 ? progressA / targetA : 0.0;
                    final percentB =
                        targetB > 0 ? progressB / targetB : 0.0;

                    return percentB.compareTo(percentA);
                  });

                  return Column(
                    children: participants.map((participant) {
                      final username = participant['username'] ?? '';
                      final uid = participant['uid'] ?? '';
                      final progress = participant['progress'] ?? 0;
                      final goalTitle = participant['goalTitle'] ?? '';
                      final targetValue = participant['targetValue'] ?? 0;
                      final unit = participant['unit'] ?? '';
                      final linkedGoalTitle =
                          participant['linkedGoalTitle'] as String?;

                      final displayName = username.toString().isNotEmpty
                          ? username
                          : uid;
                      final isMe = user != null && uid == user.uid;

                      final progressRatio = targetValue > 0
                          ? (progress / targetValue)
                          : 0.0;
                      final progressBarValue =
                          progressRatio.clamp(0.0, 1.0);
                      final percentText = targetValue > 0
                          ? '${(progressRatio * 100).toStringAsFixed(0)}%'
                          : '0%';

                      final progressText = unit.toString().isNotEmpty
                          ? '$progress / $targetValue $unit'
                          : '$progress / $targetValue completed';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe
                              ? theme.colorScheme.primary
                                  .withValues(alpha: 0.08)
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
                                    isMe
                                        ? '$displayName (You)'
                                        : displayName,
                                    style: TextStyle(
                                      fontWeight: isMe
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Text(
                                  percentText,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (isMe)
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    iconSize: 18,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Edit progress',
                                    onPressed: () =>
                                        _showEditProgressDialog(
                                      competitionId: widget.competitionId,
                                      uid: user.uid,
                                      currentProgress: progress,
                                      targetValue: targetValue,
                                      unit: unit.toString(),
                                    ),
                                  ),
                              ],
                            ),
                            if (goalTitle.toString().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(goalTitle),
                            ],
                            if (linkedGoalTitle != null &&
                                linkedGoalTitle.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.arrow_outward,
                                    size: 12,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.45),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Connected to: $linkedGoalTitle',
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.45),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              progressText,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: progressBarValue,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
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
