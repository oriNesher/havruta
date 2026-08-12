import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:marquee/marquee.dart';
import 'app_theme.dart';
import 'models/competition_event.dart';
import 'services/firestore_service.dart';
import 'services/progress_snapshot_cache.dart';
import 'competition_details_screen.dart';

// ─────────────────────────────────────────────
// Section — owns the competitions stream
// ─────────────────────────────────────────────

class HomeCompetitionsSection extends StatefulWidget {
  final String uid;
  const HomeCompetitionsSection({super.key, required this.uid});

  @override
  State<HomeCompetitionsSection> createState() =>
      _HomeCompetitionsSectionState();
}

class _HomeCompetitionsSectionState extends State<HomeCompetitionsSection> {
  late final FirestoreService _firestoreService;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _competitionsStream;

  @override
  void initState() {
    super.initState();
    _firestoreService = FirestoreService();
    _competitionsStream = _firestoreService.getUserCompetitions(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _competitionsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Column(
            children: [
              _SkeletonCompetitionCard(),
              _SkeletonCompetitionCard(),
            ],
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
            return _CompetitionCard(
              key: ValueKey(doc.id),
              competitionId: doc.id,
              competition: doc.data(),
              currentUid: widget.uid,
              firestoreService: _firestoreService,
            );
          }).toList(),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Skeleton widgets
// ─────────────────────────────────────────────

class _SkeletonBlock extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const _SkeletonBlock({
    this.width,
    required this.height,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF282840),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _SkeletonParticipantRow extends StatelessWidget {
  final bool isLast;
  const _SkeletonParticipantRow({this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: isLast ? EdgeInsets.zero : const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF202033),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Matches name row SizedBox(height: 22)
          SizedBox(
            height: 22,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _SkeletonBlock(width: 22, height: 22, radius: 11),
                const SizedBox(width: 12),
                const _SkeletonBlock(width: 88, height: 11, radius: 6),
                const Spacer(),
                const _SkeletonBlock(width: 56, height: 11, radius: 6),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Matches _ProgressBar._barHeight = 42
          const _SkeletonBlock(height: 42, radius: 21),
        ],
      ),
    );
  }
}

class _SkeletonCompetitionCard extends StatelessWidget {
  const _SkeletonCompetitionCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Matches header row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _SkeletonBlock(width: 130, height: 16, radius: 8),
                const Spacer(),
                const _SkeletonBlock(width: 36, height: 12, radius: 6),
                // Space equivalent to the PopupMenuButton icon
                const SizedBox(width: 40),
              ],
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outline.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 14),
            const _SkeletonParticipantRow(),
            const _SkeletonParticipantRow(isLast: true),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Card
// ─────────────────────────────────────────────

class _CompetitionCard extends StatelessWidget {
  final String competitionId;
  final Map<String, dynamic> competition;
  final String currentUid;
  final FirestoreService firestoreService;

  const _CompetitionCard({
    super.key,
    required this.competitionId,
    required this.competition,
    required this.currentUid,
    required this.firestoreService,
  });

  String? _daysLeft(String? deadline) {
    if (deadline == null) return null;
    try {
      final d = DateTime.parse(deadline);
      final diff = d.difference(DateTime.now()).inDays;
      if (diff > 0) return '${diff}d left';
      if (diff == 0) return 'Today';
      return 'Ended';
    } catch (_) {
      return null;
    }
  }

  void _openDetails(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CompetitionDetailsScreen(
          competitionId: competitionId,
          title: competition['title'] ?? '',
          description: competition['description'] ?? '',
          status: competition['status'] ?? '',
          createdBy: competition['createdBy'] ?? '',
          deadline: competition['deadline'] as String?,
          type: competition['type'] as String? ?? 'personalGoalChallenge',
          sharedGoalTitle: competition['sharedGoalTitle'] as String?,
          sharedTargetValue: (competition['sharedTargetValue'] as num?)?.toInt(),
          sharedUnit: competition['sharedUnit'] as String?,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final title = competition['title'] as String? ?? '';
    final status = competition['status'] as String? ?? '';
    final deadline = competition['deadline'] as String?;
    final type = competition['type'] as String? ?? 'personalGoalChallenge';
    final sharedTargetValue = (competition['sharedTargetValue'] as num?)?.toInt();
    final sharedUnit = competition['sharedUnit'] as String?;

    final isActive = status == 'active';
    final isShared = type == 'sharedGoalChallenge';
    final daysLeft = _daysLeft(deadline);

    return GestureDetector(
      onTap: () => _openDetails(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.15)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (isActive) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: colorScheme.tertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'LIVE',
                      style: AppTheme.display(
                        color: colorScheme.tertiary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ] else if (status.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${status[0].toUpperCase()}${status.substring(1)}',
                      style: AppTheme.display(
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_horiz,
                      color: colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                    color: colorScheme.surface,
                    onSelected: (v) { if (v == 'details') _openDetails(context); },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'details',
                        child: Text('View Details', style: TextStyle(color: colorScheme.onSurface)),
                      ),
                    ],
                  ),
                ],
              ),
              // ── Metadata chips ───────────────────────
              if (daysLeft != null || (isShared && sharedTargetValue != null && sharedUnit != null)) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (daysLeft != null)
                      _MetaChip(icon: Icons.calendar_today_outlined, label: daysLeft),
                    if (isShared && sharedTargetValue != null && sharedUnit != null) ...[
                      if (daysLeft != null) const SizedBox(width: 8),
                      _MetaChip(
                        icon: Icons.track_changes_outlined,
                        label: '$sharedTargetValue $sharedUnit',
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: 1,
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
              ),
              const SizedBox(height: 14),
              // ── Event carousel ───────────────────────
              _CompetitionEventCarousel(
                key: ValueKey(competitionId),
                competitionId: competitionId,
                firestoreService: firestoreService,
              ),
              // ── Participants ─────────────────────────
              _ParticipantsList(
                competitionId: competitionId,
                currentUid: currentUid,
                firestoreService: firestoreService,
                isActive: isActive,
                sharedTargetValue: sharedTargetValue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Meta chip
// ─────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colorScheme.onSurface.withValues(alpha: 0.55)),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTheme.mono(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Participants list (stateful — owns cache + participants stream)
// ─────────────────────────────────────────────

class _ParticipantsList extends StatefulWidget {
  final String competitionId;
  final String currentUid;
  final FirestoreService firestoreService;
  final bool isActive;
  final int? sharedTargetValue;

  const _ParticipantsList({
    required this.competitionId,
    required this.currentUid,
    required this.firestoreService,
    required this.isActive,
    this.sharedTargetValue,
  });

  @override
  State<_ParticipantsList> createState() => _ParticipantsListState();
}

class _ParticipantsListState extends State<_ParticipantsList> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  Map<String, int>? _lastSeenProgress;
  bool _loggingProgress = false;

  @override
  void initState() {
    super.initState();
    _stream = widget.firestoreService.getCompetitionParticipants(widget.competitionId);
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

  Future<void> _logProgress() async {
    setState(() => _loggingProgress = true);
    try {
      await widget.firestoreService.incrementMyProgress(
        competitionId: widget.competitionId,
        uid: widget.currentUid,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating progress: $e')),
      );
    } finally {
      if (mounted) setState(() => _loggingProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          // Skeleton rows match the exact height of real _ParticipantRow widgets,
          // so the card does not change size when real data arrives.
          return const Column(
            children: [
              _SkeletonParticipantRow(),
              _SkeletonParticipantRow(isLast: true),
            ],
          );
        }
        if (snap.hasError) {
          debugPrint('Participants stream error: ${snap.error}');
          return Text('Error: ${snap.error}');
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const Text('No participants yet');

        final participants = docs.map((d) => d.data()).toList();

        participants.sort((a, b) {
          final pA = (a['progress'] as num? ?? 0).toDouble();
          final pB = (b['progress'] as num? ?? 0).toDouble();
          final tA = (a['targetValue'] as num? ?? widget.sharedTargetValue ?? 1).toDouble();
          final tB = (b['targetValue'] as num? ?? widget.sharedTargetValue ?? 1).toDouble();
          return (tB > 0 ? pB / tB : 0.0).compareTo(tA > 0 ? pA / tA : 0.0);
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          ProgressSnapshotCache.instance.updateCurrent(
            widget.competitionId,
            {for (final p in participants) (p['uid'] as String): (p['progress'] as num? ?? 0).toInt()},
          );
        });

        final myData = participants.firstWhere(
          (p) => (p['uid'] as String?) == widget.currentUid,
          orElse: () => {},
        );
        final myProgress = (myData['progress'] as num? ?? 0).toInt();
        final myTarget = (myData['targetValue'] as num? ?? widget.sharedTargetValue ?? 0).toInt();
        final canLog = widget.isActive && myData.isNotEmpty && myProgress < myTarget;

        return Column(
          children: [
            ...participants.asMap().entries.map((entry) {
              final rank = entry.key;
              final p = entry.value;

              final pUid = p['uid'] as String? ?? '';
              final username = p['username'] as String? ?? pUid;
              final progress = (p['progress'] as num? ?? 0).toInt();
              final target = (p['targetValue'] as num? ?? widget.sharedTargetValue ?? 0).toInt();
              final goalTitle = p['goalTitle'] as String? ?? '';
              final unit = p['unit'] as String? ?? '';

              final isMe = pUid == widget.currentUid;
              final lastSeen = _lastSeenProgress?[pUid] ?? progress;

              final baseFraction = target > 0 ? (lastSeen / target).clamp(0.0, 1.0) : 0.0;
              final deltaFraction = target > 0
                  ? ((progress - lastSeen) / target).clamp(0.0, 1.0 - baseFraction)
                  : 0.0;
              final pct = target > 0
                  ? '${((progress / target) * 100).toStringAsFixed(0)}%'
                  : '0%';
              final progressLabel = unit.isNotEmpty ? '$progress / $target $unit' : '$progress / $target';

              return _ParticipantRow(
                rank: rank,
                username: username,
                goalTitle: goalTitle,
                progressLabel: progressLabel,
                percentText: pct,
                isMe: isMe,
                baseFraction: baseFraction,
                deltaFraction: deltaFraction,
                showLogButton: isMe && canLog,
                isLoggingProgress: _loggingProgress,
                onLogProgress: _logProgress,
              );
            }),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Event carousel — swipeable history of the existing event row widget
// ─────────────────────────────────────────────

const double _eventAreaHeight = 48.0;

class _CompetitionEventCarousel extends StatefulWidget {
  final String competitionId;
  final FirestoreService firestoreService;

  const _CompetitionEventCarousel({
    super.key,
    required this.competitionId,
    required this.firestoreService,
  });

  @override
  State<_CompetitionEventCarousel> createState() =>
      _CompetitionEventCarouselState();
}

class _CompetitionEventCarouselState extends State<_CompetitionEventCarousel> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  final PageController _pageController = PageController();

  bool _hasReceivedFirstSnapshot = false;
  String? _newestEventId;

  @override
  void initState() {
    super.initState();
    _stream = widget.firestoreService.getCompetitionEvents(widget.competitionId);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<CompetitionEvent> _sortedEvents(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final events = docs.map(CompetitionEvent.fromDoc).toList();
    events.sort((a, b) {
      final at = a.lastUpdatedAt;
      final bt = b.lastUpdatedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return events;
  }

  // Jumps back to page 0 only when a genuinely new event becomes the
  // newest one — not on unrelated rebuilds or in-place edits of existing
  // events (same newest id), so the user's current page isn't disturbed.
  void _syncNewestEvent(List<CompetitionEvent> events) {
    final newestId = events.isNotEmpty ? events.first.id : null;

    if (!_hasReceivedFirstSnapshot) {
      _hasReceivedFirstSnapshot = true;
      _newestEventId = newestId;
      return;
    }

    final isGenuinelyNew = newestId != null && newestId != _newestEventId;
    _newestEventId = newestId;
    if (!isGenuinelyNew) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  // Defends against a deleted event leaving the controller parked past the
  // new last page.
  void _clampPageIfNeeded(int eventCount) {
    if (!_pageController.hasClients) return;
    final maxIndex = eventCount - 1;
    if (maxIndex < 0) return;
    final currentPage = _pageController.page?.round() ?? 0;
    if (currentPage <= maxIndex) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      final page = _pageController.page?.round() ?? 0;
      if (page > maxIndex) {
        _pageController.jumpToPage(maxIndex);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _EventAreaWithSpacing(child: _EventPlaceholderRow());
        }

        if (snapshot.hasError) {
          debugPrint('Competition events error: ${snapshot.error}');
          _hasReceivedFirstSnapshot = false;
          _newestEventId = null;
          return const SizedBox.shrink();
        }

        final events = _sortedEvents(snapshot.data?.docs ?? []);

        if (events.isEmpty) {
          _hasReceivedFirstSnapshot = false;
          _newestEventId = null;
          return const SizedBox.shrink();
        }

        _syncNewestEvent(events);
        _clampPageIfNeeded(events.length);

        return _EventAreaWithSpacing(
          child: PageView.builder(
            controller: _pageController,
            itemCount: events.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _CompetitionEventRow(event: events[index]),
            ),
          ),
        );
      },
    );
  }
}

class _EventAreaWithSpacing extends StatelessWidget {
  final Widget child;
  const _EventAreaWithSpacing({required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: _eventAreaHeight, child: child),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _EventPlaceholderRow extends StatelessWidget {
  const _EventPlaceholderRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF282840),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Compact per-competition event row — icon + message | RESPOND
// ─────────────────────────────────────────────

class _CompetitionEventRow extends StatelessWidget {
  final CompetitionEvent event;

  const _CompetitionEventRow({required this.event});

  IconData get _icon {
    switch (event.type) {
      case 'overtook':
        return Icons.local_fire_department;
      case 'tied':
        return Icons.balance;
      case 'closeBehindYou':
        return Icons.directions_run;
      case 'tookTheLead':
        return Icons.leaderboard;
      case 'pullingAhead':
        return Icons.rocket_launch;
      case 'closeRace':
        return Icons.bolt;
      case 'progress':
        return Icons.trending_up;
      case 'backInRace':
        return Icons.replay;
      case 'nearCompletion':
        return Icons.flag;
      case 'milestone':
        return Icons.military_tech;
      case 'won':
        return Icons.emoji_events;
      case 'finishedInPosition':
        return Icons.check_circle;
      case 'activityStreak':
        return Icons.whatshot;
      case 'joined':
        return Icons.person_add;
      case 'left':
        return Icons.person_remove;
      default:
        return Icons.notifications_none;
    }
  }

  String get _message {
    final actor = event.actorUsername ?? 'Someone';
    switch (event.type) {
      case 'overtook':
        return '$actor overtook you';
      case 'tied':
        return '$actor tied with you';
      case 'closeBehindYou':
        return '$actor is closing in on you';
      case 'tookTheLead':
        return '$actor took the lead';
      case 'pullingAhead':
        return '$actor is pulling ahead';
      case 'closeRace':
        return 'Tight race for 1st place';
      case 'progress':
        return '$actor made progress';
      case 'backInRace':
        return '$actor is back in the race';
      case 'nearCompletion':
        return '$actor is almost done';
      case 'milestone':
        final pct = (event.metadata?['milestone'] as num?)?.toInt();
        return pct != null ? '$actor hit $pct%' : '$actor hit a milestone';
      case 'won':
        return '$actor won the competition';
      case 'finishedInPosition':
        final position = (event.metadata?['position'] as num?)?.toInt();
        return position != null
            ? '$actor finished ${_ordinal(position)}'
            : '$actor finished the competition';
      case 'activityStreak':
        final streak = (event.metadata?['streak'] as num?)?.toInt();
        return streak != null
            ? '$actor is on a $streak-day streak'
            : '$actor is on a streak';
      case 'joined':
        return '$actor joined the competition';
      case 'left':
        return '$actor left the competition';
      default:
        return 'New activity';
    }
  }

  static String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final red = colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: red.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 18, color: red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _message,
              style: AppTheme.display(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: red,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'RESPOND',
              style: AppTheme.display(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Single participant row
// ─────────────────────────────────────────────

class _ParticipantRow extends StatelessWidget {
  final int rank;
  final String username;
  final String goalTitle;
  final String progressLabel;
  final String percentText;
  final bool isMe;
  final double baseFraction;
  final double deltaFraction;
  final bool showLogButton;
  final bool isLoggingProgress;
  final VoidCallback? onLogProgress;

  const _ParticipantRow({
    required this.rank,
    required this.username,
    required this.goalTitle,
    required this.progressLabel,
    required this.percentText,
    required this.isMe,
    required this.baseFraction,
    required this.deltaFraction,
    this.showLogButton = false,
    this.isLoggingProgress = false,
    this.onLogProgress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRankOne = rank == 0;

    const rankOneColor = Color(0xFF7A5E18);
    final rankOtherColor = colorScheme.surfaceContainerHighest;

    final rankBadge = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: isRankOne ? rankOneColor : rankOtherColor,
        shape: BoxShape.circle,
      ),
      child: isRankOne
          ? const Icon(Icons.emoji_events, size: 12, color: Colors.white70)
          : Center(
              child: Text(
                '${rank + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF202033),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Name row — badge | name | goalTitle marquee | progress label ──
          SizedBox(
            height: 22,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                rankBadge,
                const SizedBox(width: 12),
                Text(
                  username,
                  style: TextStyle(
                    fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
                    fontSize: 14,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (goalTitle.isNotEmpty) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Marquee(
                        text: goalTitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        textDirection: TextDirection.rtl,
                        scrollAxis: Axis.horizontal,
                        blankSpace: constraints.maxWidth,
                        velocity: 30.0,
                        pauseAfterRound: Duration.zero,
                        accelerationDuration: Duration.zero,
                        decelerationDuration: Duration.zero,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                const SizedBox(width: 18),
                Text(
                  progressLabel,
                  style: AppTheme.mono(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // ── Progress bar ─────────────────────────
          _ProgressBar(
            baseFraction: baseFraction,
            deltaFraction: deltaFraction,
            percentText: percentText,
            isMe: isMe,
          ),
          if (showLogButton) ...[
            const SizedBox(height: 12),
            Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outline.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: isLoggingProgress ? null : onLogProgress,
              child: Center(
                child: isLoggingProgress
                    ? const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.add, size: 18, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'LOG PROGRESS',
                            style: AppTheme.display(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.8,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Progress bar — pill shape, % on left, circle handle
// ─────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  static const double _barHeight = 42.0;
  static const double _circleSize = _barHeight;
  static const Color _circleBorder = Color(0xFF202033);

  final double baseFraction;
  final double deltaFraction;
  final String percentText;
  final bool isMe;

  const _ProgressBar({
    required this.baseFraction,
    required this.deltaFraction,
    required this.percentText,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final fillColor = isMe ? colorScheme.tertiary : colorScheme.primary;
    final deltaColor = colorScheme.secondary;
    final trackColor = colorScheme.surface;

    final hasDelta = deltaFraction > 0.001;
    final hasFill = baseFraction + deltaFraction > 0.001;

    final circleColor = hasDelta
        ? colorScheme.secondary
        : (isMe ? colorScheme.tertiary : colorScheme.primary);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final baseW = (w * baseFraction).clamp(0.0, w);
        final deltaW = (w * deltaFraction).clamp(0.0, w - baseW);
        final fillEnd = baseW + deltaW;

        const radius = _barHeight / 2;

        return SizedBox(
          height: _barHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: SizedBox(
                  width: w,
                  height: _barHeight,
                  child: Row(
                    children: [
                      if (baseW > 0)
                        Container(
                          width: baseW,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [fillColor.withValues(alpha: 0.78), fillColor],
                            ),
                          ),
                        ),
                      if (deltaW > 0)
                        Container(
                          width: deltaW,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [deltaColor.withValues(alpha: 0.82), deltaColor],
                            ),
                          ),
                        ),
                      Expanded(child: Container(color: trackColor)),
                    ],
                  ),
                ),
              ),
              if (hasFill)
                Positioned(
                  left: (fillEnd - _circleSize / 2).clamp(0.0, w - _circleSize),
                  top: 0,
                  child: Container(
                    width: _circleSize,
                    height: _circleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: circleColor,
                      border: Border.all(color: _circleBorder, width: 3),
                    ),
                  ),
                ),
              Positioned(
                right: 14,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    percentText,
                    style: AppTheme.mono(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
