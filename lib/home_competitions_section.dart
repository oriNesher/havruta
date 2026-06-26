import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/firestore_service.dart';
import 'services/progress_snapshot_cache.dart';
import 'competition_details_screen.dart';

class HomeCompetitionsSection extends StatelessWidget {
  final String uid;
  final _firestoreService = FirestoreService();

  HomeCompetitionsSection({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestoreService.getUserCompetitions(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          debugPrint('My competitions error: ${snapshot.error}');
          return Text('Error: ${snapshot.error}');
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const Text('No competitions yet');
        }

        return Column(
          children: docs.map((doc) {
            final competition = doc.data();
            final competitionId = doc.id;
            final title = competition['title'] ?? '';
            final description = competition['description'] ?? '';
            final status = competition['status'] ?? '';
            final createdBy = competition['createdBy'] ?? '';
            final deadline = competition['deadline'] as String?;
            final type = competition['type'] as String? ?? 'personalGoalChallenge';
            final sharedGoalTitle = competition['sharedGoalTitle'] as String?;
            final sharedTargetValue =
                (competition['sharedTargetValue'] as num?)?.toInt();
            final sharedUnit = competition['sharedUnit'] as String?;

            final badgeLabel = type == 'sharedGoalChallenge'
                ? 'Shared Goal Challenge'
                : 'Personal Goal Challenge';

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CompetitionDetailsScreen(
                      competitionId: competitionId,
                      title: title,
                      description: description,
                      status: status,
                      createdBy: createdBy,
                      deadline: deadline,
                      type: type,
                      sharedGoalTitle: sharedGoalTitle,
                      sharedTargetValue: sharedTargetValue,
                      sharedUnit: sharedUnit,
                    ),
                  ),
                );
              },
              child: Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (status.isNotEmpty)
                            Text(
                              '${status[0].toUpperCase()}${status.substring(1)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: status == 'active'
                                    ? Theme.of(context).colorScheme.tertiary
                                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
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
                          badgeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      if (description.toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          description,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'Participants',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      _ParticipantsList(
                        competitionId: competitionId,
                        currentUid: uid,
                        firestoreService: _firestoreService,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _ParticipantsList extends StatefulWidget {
  final String competitionId;
  final String currentUid;
  final FirestoreService firestoreService;

  const _ParticipantsList({
    required this.competitionId,
    required this.currentUid,
    required this.firestoreService,
  });

  @override
  State<_ParticipantsList> createState() => _ParticipantsListState();
}

class _ParticipantsListState extends State<_ParticipantsList> {
  Map<String, int>? _lastSeenProgress;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
  }

  Future<void> _loadFromCache() async {
    await ProgressSnapshotCache.instance.ensureLoaded(
      widget.currentUid,
      widget.competitionId,
      widget.firestoreService,
    );
    if (mounted) {
      setState(() {
        _lastSeenProgress = ProgressSnapshotCache.instance.getPrevious(
          widget.competitionId,
        );
      });
    }
  }

  Widget _buildProgressBar(
    BuildContext context, {
    required double baseFraction,
    required double deltaFraction,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasDelta = deltaFraction > 0.001;

    return Container(
      decoration: hasDelta
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.secondary.withValues(alpha: 0.45),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          height: 18,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final baseW = (w * baseFraction).clamp(0.0, w);
              final deltaW = (w * deltaFraction).clamp(0.0, w - baseW);

              return Row(
                children: [
                  if (baseW > 0)
                    Container(width: baseW, color: colorScheme.primary),
                  if (deltaW > 0)
                    Container(width: deltaW, color: colorScheme.secondary),
                  Expanded(
                    child: Container(color: colorScheme.surfaceContainerHighest),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.firestoreService.getCompetitionParticipants(
        widget.competitionId,
      ),
      builder: (context, participantsSnapshot) {
        if (participantsSnapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (participantsSnapshot.hasError) {
          debugPrint('Participants stream error: ${participantsSnapshot.error}');
          return Text('Error: ${participantsSnapshot.error}');
        }

        final participantDocs = participantsSnapshot.data?.docs ?? [];

        if (participantDocs.isEmpty) {
          return const Text('No participants yet');
        }

        final participants = participantDocs.map((doc) => doc.data()).toList();

        participants.sort((a, b) {
          final progressA = a['progress'] ?? 0;
          final progressB = b['progress'] ?? 0;
          final targetA = a['targetValue'] ?? 0;
          final targetB = b['targetValue'] ?? 0;

          final percentA = targetA > 0 ? progressA / targetA : 0.0;
          final percentB = targetB > 0 ? progressB / targetB : 0.0;

          return percentB.compareTo(percentA);
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          ProgressSnapshotCache.instance.updateCurrent(
            widget.competitionId,
            {
              for (final p in participants)
                (p['uid'] as String): (p['progress'] as num? ?? 0).toInt(),
            },
          );
        });

        return Column(
          children: participants.map((participant) {
            final username = participant['username'] ?? '';
            final uid = participant['uid'] ?? '';
            final progress = (participant['progress'] as num? ?? 0).toInt();
            final targetValue = (participant['targetValue'] as num? ?? 0).toInt();
            final goalTitle = participant['goalTitle'] ?? '';
            final unit = participant['unit'] ?? '';

            final name = username.toString().isNotEmpty ? username : uid;
            final isMe = uid == widget.currentUid;
            final progressValue = targetValue > 0 ? (progress / targetValue) : 0.0;
            final percentText = targetValue > 0
                ? '${(progressValue * 100).toStringAsFixed(0)}%'
                : '0%';

            final lastSeen = _lastSeenProgress?[uid] ?? progress;
            final baseFraction = targetValue > 0
                ? (lastSeen / targetValue).clamp(0.0, 1.0)
                : 0.0;
            final deltaFraction = targetValue > 0
                ? ((progress - lastSeen) / targetValue).clamp(
                    0.0,
                    1.0 - baseFraction,
                  )
                : 0.0;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isMe ? '$name (You)' : name,
                          style: TextStyle(
                            fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        percentText,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  if (goalTitle.toString().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(goalTitle),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    unit.toString().isNotEmpty
                        ? '$progress / $targetValue $unit'
                        : '$progress / $targetValue completed',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (isMe) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: progress >= targetValue
                            ? null
                            : () async {
                                try {
                                  await widget.firestoreService
                                      .incrementMyProgress(
                                    competitionId: widget.competitionId,
                                    uid: widget.currentUid,
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error updating progress: $e'),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.add_circle),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  _buildProgressBar(
                    context,
                    baseFraction: baseFraction,
                    deltaFraction: deltaFraction,
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
