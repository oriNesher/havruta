import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/firestore_service.dart';

/// Event types that represent one participant reporting progress. Both carry
/// metadata.progressDelta (see functions/src/events/rules/progress.ts), and
/// rapid taps are already merged server-side into a single event.
const Set<String> kProgressReportEventTypes = {'progress', 'backInRace'};

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _weekdayNames = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];

/// Local calendar day, with the time stripped. All graph maps key on this.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The bits of a participant doc the graph needs.
class ActivityParticipant {
  final String uid;
  final String name;
  final int targetValue;
  final String unit;

  const ActivityParticipant({
    required this.uid,
    required this.name,
    required this.targetValue,
    required this.unit,
  });

  factory ActivityParticipant.fromData(Map<String, dynamic> data) {
    final uid = (data['uid'] ?? '').toString();
    final username = (data['username'] ?? '').toString();
    return ActivityParticipant(
      uid: uid,
      name: username.isNotEmpty ? username : uid,
      targetValue: (data['targetValue'] as num?)?.toInt() ?? 0,
      unit: (data['unit'] ?? '').toString(),
    );
  }
}

/// One participant's total reported progress on one day.
class DayContribution {
  final String uid;
  final String name;
  final int amount;
  final String unit;

  /// [amount] as a fraction of the participant's own target, so days can be
  /// compared across participants tracking different units (personal goal
  /// challenges). 0 when the target is unknown.
  final double score;

  const DayContribution({
    required this.uid,
    required this.name,
    required this.amount,
    required this.unit,
    required this.score,
  });
}

/// Groups progress-report events into per-day contributions — one entry per
/// participant per day, with multiple reports on the same day summed.
/// Each list is sorted largest contribution first.
Map<DateTime, List<DayContribution>> buildDailyActivity({
  required Iterable<Map<String, dynamic>> events,
  required Map<String, ActivityParticipant> participantsByUid,
}) {
  final byDay = <DateTime, Map<String, DayContribution>>{};

  for (final event in events) {
    if (!kProgressReportEventTypes.contains(event['type'])) continue;

    final uid = event['actorUid'] as String?;
    final timestamp = (event['createdAt'] ?? event['lastUpdatedAt']) as Timestamp?;
    if (uid == null || timestamp == null) continue;

    final metadata = event['metadata'] as Map<String, dynamic>?;
    final amount = (metadata?['progressDelta'] as num?)?.toInt() ?? 0;
    final participant = participantsByUid[uid];
    final target = participant?.targetValue ?? 0;

    final perUser = byDay.putIfAbsent(dateOnly(timestamp.toDate()), () => {});
    final total = (perUser[uid]?.amount ?? 0) + amount;
    perUser[uid] = DayContribution(
      uid: uid,
      name: participant?.name ?? (event['actorUsername'] as String?) ?? 'Someone',
      amount: total,
      unit: participant?.unit ?? '',
      score: target > 0 ? total / target : 0,
    );
  }

  return byDay.map(
    (day, perUser) => MapEntry(
      day,
      perUser.values.toList()..sort((a, b) => b.amount.compareTo(a.amount)),
    ),
  );
}

/// A day's graph value. Any report counts for something, even one with an
/// unknown delta or target, so an active day never renders as empty.
double dayIntensity(List<DayContribution> contributions) {
  if (contributions.isEmpty) return 0;
  final score = contributions.fold<double>(0, (total, c) => total + c.score);
  return math.max(score, 1e-6);
}

/// Maps a day's value to a color level: 0 = empty, 1..levels = increasingly
/// intense.
typedef IntensityLevelFn = int Function(double value, double maxValue, int levels);

/// Levels relative to the busiest day in view, square-root compressed so one
/// outlier day doesn't flatten everything else down to the lowest level.
int defaultIntensityLevel(double value, double maxValue, int levels) {
  if (value <= 0 || maxValue <= 0) return 0;
  final ratio = math.sqrt((value / maxValue).clamp(0.0, 1.0));
  return (ratio * levels).ceil().clamp(1, levels);
}

/// Fill color for a level, from the empty cell up to the full accent.
Color contributionLevelColor(ThemeData theme, int level, int levels) {
  if (level <= 0) return theme.colorScheme.surfaceContainerHighest;
  final t = levels <= 1 ? 1.0 : (level - 1) / (levels - 1);
  return theme.colorScheme.primary.withValues(alpha: 0.28 + 0.72 * t);
}

/// GitHub-style grid: one column per week (Sunday on top), one cell per day,
/// newest week on the right. Purely presentational — callers own the data,
/// date range, and what tapping a day does.
class ContributionGrid extends StatelessWidget {
  /// Last day shown (normally today). Days after it in its week are blank.
  final DateTime endDate;
  final int weeks;
  final Map<DateTime, double> values;
  final int levels;
  final IntensityLevelFn intensityLevel;

  /// Days drawn with an accent outline — reserved for streak visualization.
  final Set<DateTime> highlightedDays;
  final DateTime? selectedDay;
  final ValueChanged<DateTime>? onDayTap;
  final double maxCellSize;
  final double gap;

  const ContributionGrid({
    super.key,
    required this.endDate,
    required this.values,
    this.weeks = 12,
    this.levels = 4,
    this.intensityLevel = defaultIntensityLevel,
    this.highlightedDays = const {},
    this.selectedDay,
    this.onDayTap,
    this.maxCellSize = 15,
    this.gap = 3,
  });

  /// The first (Sunday) day of a [weeks]-week grid ending on [endDate].
  static DateTime startFor(DateTime endDate, int weeks) {
    final end = dateOnly(endDate);
    return DateTime(end.year, end.month, end.day - end.weekday % 7 - 7 * (weeks - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = dateOnly(endDate);
    final start = startFor(today, weeks);
    final maxValue = values.values.fold<double>(0, math.max);
    const monthLabelHeight = 16.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = ((constraints.maxWidth - gap * (weeks - 1)) / weeks)
            .clamp(6.0, maxCellSize);
        final columnWidth = cell + gap;

        final monthLabels = <Widget>[];
        final columns = <Widget>[];
        int? lastLabelColumn;

        for (var w = 0; w < weeks; w++) {
          final weekStart = DateTime(start.year, start.month, start.day + 7 * w);

          // Label the column a new month starts in, if there's room.
          final days = List.generate(
            7,
            (d) => DateTime(weekStart.year, weekStart.month, weekStart.day + d),
          );
          final monthStart = w == 0
              ? weekStart
              : days.where((d) => d.day == 1).firstOrNull;
          if (monthStart != null &&
              (lastLabelColumn == null || w - lastLabelColumn >= 3)) {
            monthLabels.add(Positioned(
              left: w * columnWidth,
              child: Text(
                _monthNames[monthStart.month - 1],
                style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
              ),
            ));
            lastLabelColumn = w;
          }

          columns.add(Padding(
            padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : gap),
            child: Column(
              children: [
                for (final day in days)
                  Padding(
                    padding: EdgeInsets.only(bottom: day.weekday == DateTime.saturday ? 0 : gap),
                    child: day.isAfter(today)
                        ? SizedBox(width: cell, height: cell)
                        : _cell(theme, day, today, cell, maxValue),
                  ),
              ],
            ),
          ));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: monthLabelHeight,
              width: columnWidth * weeks,
              child: Stack(clipBehavior: Clip.none, children: monthLabels),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: columns),
          ],
        );
      },
    );
  }

  Widget _cell(
    ThemeData theme,
    DateTime day,
    DateTime today,
    double size,
    double maxValue,
  ) {
    final level = intensityLevel(values[day] ?? 0, maxValue, levels);
    final isSelected = selectedDay == day;
    final isHighlighted = highlightedDays.contains(day);

    Border? border;
    if (isSelected) {
      border = Border.all(color: theme.colorScheme.onSurface, width: 1.5);
    } else if (isHighlighted) {
      border = Border.all(color: theme.colorScheme.tertiary, width: 1.2);
    } else if (day == today) {
      border = Border.all(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDayTap == null ? null : () => onDayTap!(day),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: contributionLevelColor(theme, level, levels),
          borderRadius: BorderRadius.circular(size * 0.22),
          border: border,
        ),
      ),
    );
  }
}

/// Compact "Less ▪▪▪▪ More" key for a [ContributionGrid].
class ContributionLegend extends StatelessWidget {
  final int levels;
  final double cellSize;

  const ContributionLegend({super.key, this.levels = 4, this.cellSize = 9});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(fontSize: 10);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Less', style: labelStyle),
        const SizedBox(width: 4),
        for (var level = 0; level <= levels; level++)
          Container(
            width: cellSize,
            height: cellSize,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: contributionLevelColor(theme, level, levels),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        const SizedBox(width: 4),
        Text('More', style: labelStyle),
      ],
    );
  }
}

/// The Challenge Details "Activity" section: one shared contribution graph
/// of every participant's progress reports, a participant filter above it,
/// and a tap-a-day sheet showing who reported what.
class ChallengeActivityGraph extends StatefulWidget {
  final String competitionId;

  /// Raw participant docs, as streamed by getCompetitionParticipants.
  final List<Map<String, dynamic>> participants;
  final String? currentUserUid;
  final int weeks;

  const ChallengeActivityGraph({
    super.key,
    required this.competitionId,
    required this.participants,
    this.currentUserUid,
    this.weeks = 12,
  });

  @override
  State<ChallengeActivityGraph> createState() => _ChallengeActivityGraphState();
}

class _ChallengeActivityGraphState extends State<ChallengeActivityGraph> {
  late final DateTime _today;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _events;

  /// null = All.
  String? _selectedUid;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _today = dateOnly(DateTime.now());
    _events = FirestoreService().getCompetitionActivitySince(
      widget.competitionId,
      ContributionGrid.startFor(_today, widget.weeks),
    );
  }

  List<ActivityParticipant> get _participants {
    final list = widget.participants
        .map(ActivityParticipant.fromData)
        .where((p) => p.uid.isNotEmpty)
        .toList();
    // Me first, then everyone else in the order the screen lists them.
    final meIndex = list.indexWhere((p) => p.uid == widget.currentUserUid);
    if (meIndex > 0) list.insert(0, list.removeAt(meIndex));
    return list;
  }

  String _nameFor(ActivityParticipant p) =>
      p.uid == widget.currentUserUid ? 'You' : p.name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final participants = _participants;
    final byUid = {for (final p in participants) p.uid: p};

    // A filtered participant who has since left the challenge falls back to All.
    final selectedUid = byUid.containsKey(_selectedUid) ? _selectedUid : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _events,
        builder: (context, snapshot) {
          final daily = buildDailyActivity(
            events: snapshot.data?.docs.map((d) => d.data()) ?? const [],
            participantsByUid: byUid,
          );
          final visible = <DateTime, List<DayContribution>>{};
          daily.forEach((day, contributions) {
            final shown = selectedUid == null
                ? contributions
                : contributions.where((c) => c.uid == selectedUid).toList();
            if (shown.isNotEmpty) visible[day] = shown;
          });

          final activeDays = visible.length;
          final whose = selectedUid == null ? null : _nameFor(byUid[selectedUid]!);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Activity', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Text(
                    'Last ${widget.weeks} weeks',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
              if (participants.length > 1) ...[
                const SizedBox(height: 8),
                _ParticipantFilter(
                  participants: participants,
                  selectedUid: selectedUid,
                  nameFor: _nameFor,
                  onSelected: (uid) => setState(() => _selectedUid = uid),
                ),
              ],
              const SizedBox(height: 10),
              Center(
                child: ContributionGrid(
                  endDate: _today,
                  weeks: widget.weeks,
                  values: visible.map((day, c) => MapEntry(day, dayIntensity(c))),
                  selectedDay: _selectedDay,
                  onDayTap: (day) => _showDay(day, visible[day] ?? const [], whose),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: snapshot.hasError
                        ? Text(
                            "Couldn't load activity",
                            style: theme.textTheme.labelSmall,
                          )
                        : Text.rich(
                            TextSpan(
                              style: theme.textTheme.labelSmall,
                              children: [
                                TextSpan(
                                  text: '$activeDays',
                                  style: AppTheme.mono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                TextSpan(
                                  text: activeDays == 1 ? ' active day' : ' active days',
                                ),
                                if (whose != null) TextSpan(text: ' · $whose'),
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  const ContributionLegend(),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showDay(
    DateTime day,
    List<DayContribution> contributions,
    String? filteredName,
  ) async {
    setState(() => _selectedDay = day);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _DaySheet(
        day: day,
        contributions: contributions,
        emptyText: filteredName == null
            ? 'Nobody reported progress this day.'
            : filteredName == 'You'
                ? "You didn't report progress this day."
                : "$filteredName didn't report progress this day.",
        currentUserUid: widget.currentUserUid,
      ),
    );
    if (mounted) setState(() => _selectedDay = null);
  }
}

class _ParticipantFilter extends StatelessWidget {
  final List<ActivityParticipant> participants;
  final String? selectedUid;
  final String Function(ActivityParticipant) nameFor;
  final ValueChanged<String?> onSelected;

  const _ParticipantFilter({
    required this.participants,
    required this.selectedUid,
    required this.nameFor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allSelected = selectedUid == null;

    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          GestureDetector(
            onTap: () => onSelected(null),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: allSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'All',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: allSelected ? theme.colorScheme.onPrimary : null,
                ),
              ),
            ),
          ),
          for (final p in participants) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: nameFor(p),
              child: GestureDetector(
                // Tapping the active filter again goes back to All.
                onTap: () => onSelected(selectedUid == p.uid ? null : p.uid),
                child: _InitialAvatar(
                  name: p.name,
                  size: 30,
                  selected: selectedUid == p.uid,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  final String name;
  final double size;
  final bool selected;

  const _InitialAvatar({
    required this.name,
    required this.size,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: selected ? theme.colorScheme.primary : theme.dividerColor,
        ),
      ),
      child: Text(
        initial,
        style: AppTheme.display(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w700,
          color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
          height: 1,
        ),
      ),
    );
  }
}

class _DaySheet extends StatelessWidget {
  final DateTime day;
  final List<DayContribution> contributions;
  final String emptyText;
  final String? currentUserUid;

  const _DaySheet({
    required this.day,
    required this.contributions,
    required this.emptyText,
    this.currentUserUid,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title =
        '${_weekdayNames[day.weekday - 1]}, ${_monthNames[day.month - 1]} ${day.day}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (contributions.isEmpty)
              Text(emptyText, style: theme.textTheme.bodySmall)
            else
              for (final c in contributions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      _InitialAvatar(name: c.name, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          c.uid == currentUserUid ? '${c.name} (You)' : c.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (c.amount > 0)
                        Text(
                          c.unit.isNotEmpty ? '+${c.amount} ${c.unit}' : '+${c.amount}',
                          style: AppTheme.mono(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
