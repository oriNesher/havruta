import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:marquee/marquee.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../app_theme.dart';
import '../competitions/challenge.dart';
import '../competitions/challenge_standings.dart';
import '../competitions/competition_event.dart';
import '../competitions/progress_reporting.dart';
import '../competitions/widgets/add_progress.dart';
import '../competitions/widgets/personal_progress_panel.dart';
import '../onboarding/onboarding_anchor.dart';
import '../onboarding/onboarding_ids.dart';
import '../services/firestore_service.dart';
import '../services/progress_snapshot_cache.dart';
import '../services/respect_service.dart';
import '../services/respect_store.dart';
import '../competitions/competition_details_screen.dart';

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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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

  String? _daysLeft(Challenge challenge) {
    final now = DateTime.now();
    final startsAt = challenge.startsAt;
    if (startsAt != null && now.isBefore(startsAt)) {
      final days = DateTime(startsAt.year, startsAt.month, startsAt.day)
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;
      return days <= 1 ? 'Starts tomorrow' : 'Starts in ${days}d';
    }

    final endsAt = challenge.endsAt;
    if (endsAt != null) {
      final remaining = endsAt.difference(now);
      if (remaining.isNegative) return 'Ended';
      if (remaining.inHours < 24) return 'Last day';
      return '${remaining.inDays}d left';
    }

    // Older challenges' free-text deadline, when it happens to be a date.
    final deadline = challenge.legacyDeadline;
    if (deadline == null) return null;
    try {
      final d = DateTime.parse(deadline);
      final diff = d.difference(now).inDays;
      if (diff > 0) return '${diff}d left';
      if (diff == 0) return 'Today';
      return 'Ended';
    } catch (_) {
      return null;
    }
  }

  /// The goal chip: the race's finish line or the daily minimum.
  String? _goalChipLabel(Challenge challenge) {
    final unitSuffix = challenge.unit.isNotEmpty ? ' ${challenge.unit}' : '';
    final minimum = challenge.rules.dailyMinimum;
    return switch (challenge.winCondition) {
      WinCondition.firstToTarget
          when challenge.targetValue != null && challenge.unit.isNotEmpty =>
        challenge.targetLabel,
      WinCondition.lastStanding when minimum != null =>
        '$minimum$unitSuffix / day',
      _ => null,
    };
  }

  void _openDetails(BuildContext context, Challenge challenge) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CompetitionDetailsScreen(challenge: challenge),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final challenge = Challenge.fromDoc(competitionId, competition);
    final title = challenge.title;
    final status = challenge.status;

    final isActive = challenge.isActive;
    final daysLeft = _daysLeft(challenge);
    final goalChip = _goalChipLabel(challenge);

    return GestureDetector(
      onTap: () => _openDetails(context, challenge),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.15)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────
              OnboardingAnchor(
                id: OnboardingAnchorIds.homeChallengeCard(competitionId),
                child: Row(
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
                  ],
                ),
              ),
              if (challenge.prize != null) ...[
                const SizedBox(height: 6),
                _PrizeBadge(prize: challenge.prize!),
              ],
              // ── Metadata chips ───────────────────────
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (!challenge.isLegacyPersonal)
                    _MetaChip(
                      icon: Icons.sports_score_outlined,
                      label: challenge.winCondition.label,
                    ),
                  if (daysLeft != null)
                    _MetaChip(icon: Icons.calendar_today_outlined, label: daysLeft),
                  if (goalChip != null)
                    _MetaChip(
                      icon: Icons.track_changes_outlined,
                      label: goalChip,
                    ),
                ],
              ),
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
                currentUid: currentUid,
                firestoreService: firestoreService,
              ),
              // ── Participants ─────────────────────────
              _ParticipantsList(
                challenge: challenge,
                currentUid: currentUid,
                firestoreService: firestoreService,
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
// Prize badge — what the winner gets, under the title
// ─────────────────────────────────────────────

class _PrizeBadge extends StatelessWidget {
  final String prize;

  const _PrizeBadge({required this.prize});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.card_giftcard, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              prize,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.display(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: color,
              ),
            ),
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
  final Challenge challenge;
  final String currentUid;
  final FirestoreService firestoreService;

  const _ParticipantsList({
    required this.challenge,
    required this.currentUid,
    required this.firestoreService,
  });

  String get competitionId => challenge.id;

  @override
  State<_ParticipantsList> createState() => _ParticipantsListState();
}

/// One participant row's numbers for the card's win condition.
class _RowStats {
  /// Where the bar sits now, and how much of that is new since last visit
  /// (both 0..1 of the bar).
  final double baseFraction;
  final double deltaFraction;

  /// Shown inside the bar, e.g. "64%", "42", "20/30" or "OUT".
  final String barText;

  /// Shown top-right, e.g. "64 / 100 km".
  final String label;

  const _RowStats({
    required this.baseFraction,
    required this.deltaFraction,
    required this.barText,
    required this.label,
  });

  /// [value] / [scale] split into the part already seen and the part new
  /// since the viewer's last visit ([newAmount]).
  static (double, double) _split(num value, num newAmount, num scale) {
    if (scale <= 0) return (0, 0);
    final base = ((value - newAmount) / scale).clamp(0.0, 1.0);
    final delta = (newAmount / scale).clamp(0.0, 1.0 - base);
    return (base, delta);
  }

  factory _RowStats.of(
    Challenge challenge,
    Map<String, dynamic> participant, {
    required int lastSeen,
    required int leaderProgress,
  }) {
    final progress = (participant['progress'] as num? ?? 0).toInt();
    final unit = participant['unit'] as String? ?? challenge.unit;
    final unitSuffix = unit.isNotEmpty ? ' $unit' : '';
    final newAmount = (progress - lastSeen).clamp(0, progress);

    switch (challenge.winCondition) {
      case WinCondition.firstToTarget:
        final target = challenge.targetFor(participant) ?? 0;
        final (base, delta) = _split(progress, newAmount, target);
        return _RowStats(
          baseFraction: base,
          deltaFraction: delta,
          barText: target > 0
              ? '${((progress / target) * 100).toStringAsFixed(0)}%'
              : '0%',
          label: '$progress / $target$unitSuffix',
        );
      case WinCondition.mostProgress:
        final (base, delta) = _split(progress, newAmount, leaderProgress);
        return _RowStats(
          baseFraction: base,
          deltaFraction: delta,
          barText: '$progress',
          label: '$progress$unitSuffix',
        );
      case WinCondition.lastStanding:
        if (participant['eliminatedOnDay'] != null) {
          return _RowStats(
            baseFraction: 0,
            deltaFraction: 0,
            barText: 'OUT',
            label: '$progress$unitSuffix total',
          );
        }
        final minimum = challenge.rules.dailyMinimum ?? 0;
        final today =
            ((participant['dailyProgress'] as Map<String, dynamic>?)?[challenge
                        .dayKey(DateTime.now())]
                    as num? ??
                0)
            .toInt();
        final (base, delta) = _split(
          today,
          newAmount.clamp(0, today),
          minimum,
        );
        return _RowStats(
          baseFraction: base,
          deltaFraction: delta,
          barText: today >= minimum && minimum > 0 ? 'SAFE' : '$today/$minimum',
          label: 'today$unitSuffix',
        );
    }
  }
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

  Future<void> _openAddProgressPopup(Map<String, dynamic> me) => reportProgress(
    context,
    challenge: widget.challenge,
    me: me,
    uid: widget.currentUid,
    onSubmitting: (submitting) =>
        setState(() => _loggingProgress = submitting),
  );

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

        final challenge = widget.challenge;
        final participants = rankParticipants(
          challenge,
          docs.map((d) => d.data()),
        );
        final leaderProgress = participants
            .map((p) => (p['progress'] as num? ?? 0).toInt())
            .fold<int>(0, (a, b) => a > b ? a : b);

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
        final canLog = myData.isNotEmpty && canLogProgress(challenge, myData);

        final leaderboard = Column(
          children: [
            ...participants.asMap().entries.map((entry) {
              final rank = entry.key;
              final p = entry.value;

              final pUid = p['uid'] as String? ?? '';
              final username = p['username'] as String? ?? pUid;
              final progress = (p['progress'] as num? ?? 0).toInt();
              final goalTitle = p['goalTitle'] as String? ?? '';

              final isMe = pUid == widget.currentUid;
              final stats = _RowStats.of(
                challenge,
                p,
                lastSeen: _lastSeenProgress?[pUid] ?? progress,
                leaderProgress: leaderProgress,
              );

              return _ParticipantRow(
                rank: rank,
                username: username,
                goalTitle: goalTitle,
                progressLabel: stats.label,
                percentText: stats.barText,
                isMe: isMe,
                baseFraction: stats.baseFraction,
                deltaFraction: stats.deltaFraction,
              );
            }),
          ],
        );

        return Column(
          children: [
            // A participant sees their own progress first, the leaderboard a
            // swipe away; anyone else just the leaderboard.
            if (myData.isNotEmpty)
              _ProgressCarousel(
                progress: PersonalProgressPanel(
                  challenge: challenge,
                  me: myData,
                  compact: true,
                ),
                leaderboard: leaderboard,
              )
            else
              leaderboard,
            // Pinned below the (re-orderable) rows instead of on "my" row
            // itself — otherwise overtaking someone reshuffles the
            // leaderboard mid-tap and a spammed tap can land on the card
            // behind where the button used to be, opening competition details.
            if (canLog) _AddProgressButton(
              competitionId: widget.competitionId,
              isLoggingProgress: _loggingProgress,
              onTap: () => _openAddProgressPopup(myData),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Progress carousel — your progress first, the leaderboard a swipe away
// ─────────────────────────────────────────────

/// Two pages exactly as tall as [progress]: the viewer's own progress, then
/// [leaderboard], which scrolls inside that height when it's longer — so
/// the card (and the Add Progress button under it) never changes size on a
/// swipe. Always opens on the progress page. Taps anywhere but the dots
/// fall through to the card, which opens Challenge Details.
class _ProgressCarousel extends StatefulWidget {
  final Widget progress;
  final Widget leaderboard;

  const _ProgressCarousel({required this.progress, required this.leaderboard});

  @override
  State<_ProgressCarousel> createState() => _ProgressCarouselState();
}

class _ProgressCarouselState extends State<_ProgressCarousel> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const pageCount = 2;

    return Column(
      children: [
        Stack(
          children: [
            // An invisible copy of the progress view sets the height of both
            // pages.
            SizedBox(
              width: double.infinity,
              child: Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: widget.progress,
              ),
            ),
            Positioned.fill(
              child: PageView(
                controller: _controller,
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  widget.progress,
                  SingleChildScrollView(child: widget.leaderboard),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < pageCount; i++)
              GestureDetector(
                // Opaque, so tapping a dot never opens the card behind it.
                behavior: HitTestBehavior.opaque,
                onTap: () => _controller.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _page ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? colorScheme.primary
                          : colorScheme.onSurface.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Event carousel — swipeable history of the existing event row widget
// ─────────────────────────────────────────────

const double _eventAreaHeight = 48.0;
const Duration _nudgeInterval = Duration(seconds: 30);
const double _nudgeDistance = 22.0;

class _CompetitionEventCarousel extends StatefulWidget {
  final String competitionId;
  final String currentUid;
  final FirestoreService firestoreService;

  const _CompetitionEventCarousel({
    super.key,
    required this.competitionId,
    required this.currentUid,
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

  List<CompetitionEvent> _latestEvents = const [];
  int _currentPage = 0;
  bool _isUserDragging = false;
  bool _isNudging = false;
  Timer? _nudgeTimer;

  @override
  void initState() {
    super.initState();
    _stream = widget.firestoreService.getCompetitionEvents(widget.competitionId);
    _nudgeTimer = Timer.periodic(_nudgeInterval, (_) => _performNudge());
    OnboardingAnchorRegistry.instance.addRevealer(_revealAnchor);
  }

  @override
  void dispose() {
    OnboardingAnchorRegistry.instance.removeRevealer(_revealAnchor);
    _nudgeTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // PageView only builds the visible page, so an event's anchors don't
  // exist while it's swiped away. Turns to the page holding the event an
  // anchor id belongs to, when asked — only while this screen is on top.
  bool _revealAnchor(String anchorId) {
    if (!mounted || !_pageController.hasClients) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final index = _latestEvents.indexWhere(
      (e) =>
          OnboardingAnchorIds.homeEvent(e.id) == anchorId ||
          OnboardingAnchorIds.homeEventRespect(e.id) == anchorId,
    );
    if (index < 0 || _pageController.page?.round() == index) return false;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    return true;
  }

  // ── Unread tracking ──────────────────────────

  int get _unreadCount => _latestEvents
      .where((e) => e.unseenByUserUids.contains(widget.currentUid))
      .length;

  // Index of the unread event closest to the current page, ignoring the
  // current page itself (there's nothing to nudge/point *toward* if the
  // only unread event is already centered). Used only to pick the nudge's
  // direction — the badge itself always sits on the right.
  int? _nearestUnreadIndex() {
    int? nearest;
    int bestDistance = 1 << 30;
    for (var i = 0; i < _latestEvents.length; i++) {
      if (i == _currentPage) continue;
      if (!_latestEvents[i].unseenByUserUids.contains(widget.currentUid)) {
        continue;
      }
      final distance = (i - _currentPage).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = i;
      }
    }
    return nearest;
  }

  // true = unread events are ahead (higher index), false = behind (lower
  // index), null = no direction to point (only the current page is unread).
  bool? _unreadIsAhead() {
    final nearest = _nearestUnreadIndex();
    if (nearest == null) return null;
    return nearest > _currentPage;
  }

  // ── Mark as seen ──────────────────────────────
  // Swiping to a new page marks both the page left behind and the page
  // landed on as seen. The very first event is shown without any swipe, so
  // it only gets marked seen by a direct tap (below) or by swiping away
  // from it.

  void _onPageChanged(int page) {
    final previousPage = _currentPage;
    _currentPage = page;
    if (_isUserDragging) {
      _markSeenByIndices({previousPage, page});
    }
    setState(() {});
  }

  Future<void> _markSeenByIndices(Set<int> indices) async {
    final refs = <DocumentReference<Map<String, dynamic>>>[];
    for (final i in indices) {
      if (i < 0 || i >= _latestEvents.length) continue;
      final event = _latestEvents[i];
      if (event.unseenByUserUids.contains(widget.currentUid)) {
        refs.add(event.reference);
      }
    }
    if (refs.isEmpty) return;
    try {
      await widget.firestoreService.dismissEventsForUser(refs, widget.currentUid);
    } catch (e) {
      debugPrint('Failed to mark event(s) as seen: $e');
    }
  }

  // ── Nudge animation ──────────────────────────

  Future<void> _performNudge() async {
    if (_isNudging || _isUserDragging || !mounted) return;
    if (_unreadCount == 0) return;
    if (!_pageController.hasClients) return;

    final ahead = _unreadIsAhead();
    if (ahead == null) return;

    final position = _pageController.position;
    final start = position.pixels;
    final delta = ahead ? _nudgeDistance : -_nudgeDistance;
    final target = (start + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == start) return;

    _isNudging = true;
    try {
      await _pageController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
      if (!mounted || !_pageController.hasClients) return;
      await _pageController.animateTo(
        start,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeIn,
      );
    } catch (_) {
      // Controller may have been disposed mid-animation.
    } finally {
      _isNudging = false;
    }
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
          _latestEvents = const [];
          return const SizedBox.shrink();
        }

        final events = _sortedEvents(snapshot.data?.docs ?? []);

        if (events.isEmpty) {
          _hasReceivedFirstSnapshot = false;
          _newestEventId = null;
          _latestEvents = const [];
          return const SizedBox.shrink();
        }

        _syncNewestEvent(events);
        _clampPageIfNeeded(events.length);
        _latestEvents = events;
        if (_currentPage > events.length - 1) {
          _currentPage = events.length - 1;
        }

        final unreadCount = _unreadCount;

        final carousel = NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification &&
                notification.dragDetails != null) {
              _isUserDragging = true;
            } else if (notification is ScrollEndNotification) {
              _isUserDragging = false;
            }
            return false;
          },
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: events.length,
            // The anchor spans the whole page, so bringing it into view
            // can't leave the carousel parked between pages.
            itemBuilder: (context, index) => OnboardingAnchor(
              id: OnboardingAnchorIds.homeEvent(events[index].id),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _markSeenByIndices({index}),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _CompetitionEventRow(
                    event: events[index],
                    currentUid: widget.currentUid,
                  ),
                ),
              ),
            ),
          ),
        );

        return _EventAreaWithSpacing(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: carousel),
              if (unreadCount > 0) ...[
                const SizedBox(width: 6),
                _UnreadBadge(count: unreadCount),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Unread events badge — small red circle with a count
// ─────────────────────────────────────────────

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: colorScheme.secondary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        count > 9 ? '9+' : '$count',
        style: AppTheme.display(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
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
  final String currentUid;

  const _CompetitionEventRow({required this.event, required this.currentUid});

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
      case 'firstBlood':
        return Icons.bloodtype;
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
      case 'eliminated':
        return Icons.heart_broken;
      default:
        return Icons.notifications_none;
    }
  }

  // "You" whenever the name in question is whoever's looking at the card —
  // works for actor or target, since the carousel is shown to every
  // participant, not just the event's original recipient.
  String _labelFor(String? uid, String? username) {
    if (uid != null && uid == currentUid) return 'You';
    return username ?? 'Someone';
  }

  InlineSpan _name(String label, TextStyle base) {
    return TextSpan(
      text: label,
      style: label == 'You' ? base.copyWith(fontWeight: FontWeight.w800) : base,
    );
  }

  List<InlineSpan> _messageSpans(TextStyle base) {
    final actor = _labelFor(event.actorUid, event.actorUsername);
    final target = _labelFor(event.targetUid, event.targetUsername);
    InlineSpan name(String label) => _name(label, base);
    TextSpan text(String s) => TextSpan(text: s, style: base);

    switch (event.type) {
      case 'overtook':
        return [name(actor), text(' overtook '), name(target)];
      case 'tied':
        return [name(actor), text(' tied with '), name(target)];
      case 'closeBehindYou':
        return [name(actor), text(' is closing in on '), name(target)];
      case 'tookTheLead':
        return [name(actor), text(' took the lead')];
      case 'pullingAhead':
        return [name(actor), text(' is pulling ahead')];
      case 'closeRace':
        return [text('Tight race for 1st place')];
      case 'progress':
        final delta = (event.metadata?['progressDelta'] as num?)?.toInt();
        return [
          name(actor),
          text(delta != null ? ' made progress (+$delta)' : ' made progress'),
        ];
      case 'firstBlood':
        return [name(actor), text(' got first blood')];
      case 'backInRace':
        return [name(actor), text(' is back in the race')];
      case 'nearCompletion':
        return [name(actor), text(' is almost done')];
      case 'milestone':
        final pct = (event.metadata?['milestone'] as num?)?.toInt();
        return [
          name(actor),
          text(pct != null ? ' hit $pct%' : ' hit a milestone'),
        ];
      case 'won':
        return [name(actor), text(' won the challenge')];
      case 'finishedInPosition':
        final position = (event.metadata?['position'] as num?)?.toInt();
        return [
          name(actor),
          text(
            position != null
                ? ' finished ${_ordinal(position)}'
                : ' finished the challenge',
          ),
        ];
      case 'activityStreak':
        final streak = (event.metadata?['streak'] as num?)?.toInt();
        return [
          name(actor),
          text(
            streak != null
                ? ' is on a $streak-day streak'
                : ' is on a streak',
          ),
        ];
      case 'joined':
        return [name(actor), text(' joined the challenge')];
      case 'left':
        return [name(actor), text(' left the challenge')];
      case 'eliminated':
        final day = (event.metadata?['dayNumber'] as num?)?.toInt();
        return [
          name(actor),
          text(day != null ? ' missed day $day and is out' : ' is out'),
        ];
      default:
        return [text('New activity')];
    }
  }

  String get _relativeTime {
    final dt = (event.lastUpdatedAt ?? event.createdAt)?.toDate();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.month}/${dt.day}';
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

  bool get _canGiveRespect =>
      event.actorUid != null && event.actorUid != currentUid;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final red = colorScheme.secondary;
    final base = AppTheme.display(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
    );

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
            child: Text.rich(
              TextSpan(children: _messageSpans(base)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_canGiveRespect) ...[
            const SizedBox(width: 8),
            OnboardingAnchor(
              id: OnboardingAnchorIds.homeEventRespect(event.id),
              child: _GiveRespectButton(event: event, currentUid: currentUid),
            ),
          ],
          const SizedBox(width: 8),
          Text(
            _relativeTime,
            style: AppTheme.display(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Give Respect button — one icon, two states: an outline while ungiven,
// filled solid once given. A user can give at most one Respect per event
// (enforced server-side), so there's nothing else to show alongside it —
// no separate badge or counter.
// ─────────────────────────────────────────────

class _GiveRespectButton extends StatefulWidget {
  final CompetitionEvent event;
  final String currentUid;

  const _GiveRespectButton({required this.event, required this.currentUid});

  @override
  State<_GiveRespectButton> createState() => _GiveRespectButtonState();
}

class _GiveRespectButtonState extends State<_GiveRespectButton> {
  static final _service = RespectService();

  bool _optimisticallyGiven = false;
  bool _submitting = false;

  bool get _given =>
      widget.event.respectGivenBy.contains(widget.currentUid) ||
      _optimisticallyGiven;

  Future<void> _handleTap() async {
    if (_given || _submitting) return;
    if (RespectStore.instance.displayBalance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're out of Respect for today")),
      );
      return;
    }

    setState(() {
      _optimisticallyGiven = true;
      _submitting = true;
    });
    RespectStore.instance.beginSpend();

    try {
      final newBalance = await _service.giveRespect(
        competitionId: widget.event.competitionId,
        eventId: widget.event.id,
      );
      RespectStore.instance.endSpend(success: true, newBalance: newBalance);
    } catch (e) {
      RespectStore.instance.endSpend(success: false);
      if (mounted) setState(() => _optimisticallyGiven = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not give Respect: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same tonal-emphasis idiom as the relative-time text next to it
    // (onSurface at partial opacity for secondary/inactive, full opacity
    // once given) rather than a separate accent color — visible against the
    // dark card either way, with no color swap needed to read as "on".
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: Icon(
        _given ? PhosphorIconsFill.pawPrint : PhosphorIconsRegular.pawPrint,
        size: 20,
        color: _given ? onSurface : onSurface.withValues(alpha: 0.55),
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

  const _ParticipantRow({
    required this.rank,
    required this.username,
    required this.goalTitle,
    required this.progressLabel,
    required this.percentText,
    required this.isMe,
    required this.baseFraction,
    required this.deltaFraction,
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
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Add progress button — pinned below the participant rows
// ─────────────────────────────────────────────

class _AddProgressButton extends StatelessWidget {
  final String competitionId;
  final bool isLoggingProgress;
  final VoidCallback onTap;

  const _AddProgressButton({
    required this.competitionId,
    required this.isLoggingProgress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        const SizedBox(height: 2),
        Divider(
          height: 1,
          thickness: 1,
          color: colorScheme.outline.withValues(alpha: 0.12),
        ),
        const SizedBox(height: 12),
        Center(
          // Swallows taps over this area so they never fall through to the
          // card's own GestureDetector — otherwise, while the button is
          // briefly disabled (onPressed: null) right after logging, a tap
          // here would bubble up and open the details screen.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: OnboardingAnchor(
              id: OnboardingAnchorIds.addProgressButton(competitionId),
              child: AddProgressButton(
                isLoggingProgress: isLoggingProgress,
                onTap: onTap,
              ),
            ),
          ),
        ),
      ],
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
