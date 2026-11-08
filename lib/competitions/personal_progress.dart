import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'challenge.dart';

/// The viewer's own progress in a challenge, worked out for the Challenge
/// Details "Your progress" view: a headline number plus what each mode's
/// visualization draws. Pure — no widgets — so the panel only paints.

/// Percent marks a race celebrates on the way to its target. Hand-synced
/// with MILESTONE_THRESHOLDS in functions/src/events/rules/progression.ts,
/// so a ring segment fills exactly when its milestone celebration fires.
const List<int> kRaceMilestones = [25, 50, 75, 90];

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// 1250 → "1,250".
String formatCount(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Whole percent of [target] that [progress] reaches, rounded down so 100%
/// never shows before the target is actually hit. Integer math, so 29 of
/// 100 is 29 — not 28 from 0.29 * 100 landing just under.
int percentOf(int progress, int target) =>
    target > 0 ? math.max(0, progress) * 100 ~/ target : 0;

/// "2026-10-23" → "Oct 23".
String shortDayLabel(String dayKey) {
  final day = DateTime.parse(dayKey);
  return '${_monthNames[day.month - 1]} ${day.day}';
}

/// The big number at the top of the view, what it counts, and one line of
/// context under it.
class ProgressHeadline {
  final String value;
  final String label;
  final String caption;

  /// The caption is good news to show off (today's minimum met, a race
  /// finished, progress logged today).
  final bool captionPositive;

  const ProgressHeadline({
    required this.value,
    required this.label,
    this.caption = '',
    this.captionPositive = false,
  });
}

sealed class PersonalProgress {
  final ProgressHeadline headline;

  const PersonalProgress(this.headline);

  /// [me] is the viewer's raw participants/{uid} doc. [maxCalendarWeeks]
  /// caps how many weeks a Last One Standing calendar shows.
  factory PersonalProgress.of(
    Challenge challenge,
    Map<String, dynamic> me, {
    DateTime? now,
    int maxCalendarWeeks = 6,
  }) {
    final at = now ?? DateTime.now();
    return switch (challenge.winCondition) {
      WinCondition.firstToTarget => _raceOf(challenge, me),
      WinCondition.mostProgress => GrowthProgress._of(challenge, me, at),
      WinCondition.lastStanding =>
        StreakProgress._of(challenge, me, at, maxCalendarWeeks),
    };
  }
}

/// Race: how much of the target is done, drawn as a milestone ring.
class RaceProgress extends PersonalProgress {
  final int progress;
  final int target;

  const RaceProgress(super.headline, {required this.progress, required this.target});

  double get fraction => (progress / target).clamp(0.0, 1.0);

  /// The next milestone percent still ahead, or null once finished.
  int? get nextMilestone {
    final percent = percentOf(progress, target);
    for (final mark in [...kRaceMilestones, 100]) {
      if (percent < mark) return mark;
    }
    return null;
  }
}

/// A race with no usable target (old data): just the running total.
class TotalOnlyProgress extends PersonalProgress {
  const TotalOnlyProgress(super.headline);
}

/// Most Progress: the running total per challenge day, drawn as a growth
/// curve across the challenge's timeline.
class GrowthProgress extends PersonalProgress {
  /// Running total at the end of each day from [startDay] through today
  /// (or the last day, once over). The last entry is always the real total.
  final List<int> totals;

  /// Days on the timeline, [startDay] through [lastDay]. More than
  /// [totals] has entries while the end date is still ahead.
  final int totalDays;
  final String startDay;
  final String lastDay;
  final bool isOver;
  final String unit;

  const GrowthProgress(
    super.headline, {
    required this.totals,
    required this.totalDays,
    required this.startDay,
    required this.lastDay,
    required this.isOver,
    required this.unit,
  });

  bool get hasFuture => totals.length < totalDays;

  factory GrowthProgress._of(
    Challenge challenge,
    Map<String, dynamic> me,
    DateTime now,
  ) {
    final progress = _progressOf(me);
    final unit = _unitOf(challenge, me);
    final unitSuffix = unit.isNotEmpty ? ' $unit' : '';
    final daily = _dailyOf(me);
    final today = challenge.dayKey(now);

    // Your timeline starts the day you joined (the creator joins at
    // creation); anything logged earlier than that still counts from its day.
    final firstLogged = daily.keys.isEmpty ? null : (daily.keys.toList()..sort()).first;
    var start = _joinedDay(challenge, me) ?? firstLogged ?? today;
    if (firstLogged != null && firstLogged.compareTo(start) < 0) start = firstLogged;
    if (start.compareTo(today) > 0) start = today;

    final endsAt = challenge.endsAt;
    var last = endsAt != null ? _lastDayOf(challenge, endsAt) : today;
    if (last.compareTo(start) < 0) last = start;
    final dataEnd = today.compareTo(last) < 0 ? today : last;

    final elapsed = daysBetweenDayKeys(start, dataEnd) + 1;
    final totals = <int>[];
    var running = 0;
    for (var i = 0; i < elapsed; i++) {
      running += daily[addDaysToDayKey(start, i)] ?? 0;
      totals.add(running);
    }
    // Edits only take progress back off today's bucket, so the days can sum
    // to more than the real total; end the curve on the real total.
    totals[totals.length - 1] = progress;

    final isOver =
        !challenge.isActive || (endsAt != null && !now.isBefore(endsAt));
    final todayAmount = daily[today] ?? 0;

    return GrowthProgress(
      ProgressHeadline(
        value: formatCount(progress),
        label: unit.isNotEmpty ? unit : 'total',
        caption: isOver
            ? 'Ended ${shortDayLabel(last)}'
            : todayAmount > 0
            ? '+${formatCount(todayAmount)}$unitSuffix today'
            : 'Nothing logged today yet',
        captionPositive: !isOver && todayAmount > 0,
      ),
      totals: totals,
      totalDays: daysBetweenDayKeys(start, last) + 1,
      startDay: start,
      lastDay: last,
      isOver: isOver,
      unit: unit,
    );
  }
}

enum StreakDayStatus {
  /// A finished day with the minimum met.
  made,

  /// A finished day under the minimum, or the day you were knocked out.
  missed,

  /// Today, minimum not met yet.
  today,

  /// Today, minimum already met — safe, though it only counts as survived
  /// once the day ends.
  todayMade,

  /// Still ahead.
  upcoming,

  /// Not yours to judge: before you joined, after you were out, or after
  /// the challenge ended.
  inactive,
}

class StreakDay {
  final String dayKey;
  final StreakDayStatus status;

  /// Today's progress as a share of the minimum (0..1); 0 for other days.
  final double todayFraction;

  const StreakDay({
    required this.dayKey,
    required this.status,
    this.todayFraction = 0,
  });

  int get dayOfMonth => int.parse(dayKey.substring(8));
}

/// Last One Standing: days survived, drawn as a calendar of made and missed
/// days.
class StreakProgress extends PersonalProgress {
  /// Sunday-first week rows, 7 cells each; null cells fall outside the
  /// challenge.
  final List<StreakDay?> cells;

  /// Earlier or later weeks left out to keep the calendar compact.
  final int hiddenWeeks;

  /// Finished days the minimum was met on.
  final int survived;

  /// Days from day 1 to the end date; null with no end date.
  final int? totalDays;

  final int todayAmount;
  final int minimum;

  /// Day number the viewer was knocked out on; null while still in.
  final int? outOnDay;

  /// Day 1, while it's still ahead; null once started.
  final String? startsOn;

  final bool isOver;

  const StreakProgress(
    super.headline, {
    required this.cells,
    required this.hiddenWeeks,
    this.survived = 0,
    this.totalDays,
    this.todayAmount = 0,
    this.minimum = 0,
    this.outOnDay,
    this.startsOn,
    this.isOver = false,
  });

  int get shownWeeks => cells.length ~/ 7;

  factory StreakProgress._of(
    Challenge challenge,
    Map<String, dynamic> me,
    DateTime now,
    int maxWeeks,
  ) {
    final minimum = challenge.rules.dailyMinimum ?? 0;
    final unit = _unitOf(challenge, me);
    final unitSuffix = unit.isNotEmpty ? ' $unit' : '';
    final daily = _dailyOf(me);
    final today = challenge.dayKey(now);
    final startsAt = challenge.startsAt;
    final joined = _joinedDay(challenge, me);
    final startDay = startsAt != null
        ? challenge.dayKey(startsAt)
        : joined ?? today;
    // Judged from day 1, or from the day you joined if later — as the
    // server's evaluateLastStanding does.
    final firstJudged =
        joined != null && joined.compareTo(startDay) > 0 ? joined : startDay;
    final out = me['eliminatedOnDay'] as String?;
    final endsAt = challenge.endsAt;
    final lastDay = endsAt != null ? _lastDayOf(challenge, endsAt) : null;
    final isOver = !challenge.isActive;
    final lastEvaluated = challenge.lastEvaluatedDay;
    bool made(String day) => (daily[day] ?? 0) >= minimum;

    // Days survived: finished days you met the minimum on. Today only
    // counts once it's over.
    var closedThrough = addDaysToDayKey(today, -1);
    if (lastDay != null && lastDay.compareTo(closedThrough) < 0) {
      closedThrough = lastDay;
    }
    if (isOver &&
        lastEvaluated != null &&
        lastEvaluated.compareTo(closedThrough) < 0) {
      closedThrough = lastEvaluated;
    }
    if (out != null) {
      final beforeOut = addDaysToDayKey(out, -1);
      if (beforeOut.compareTo(closedThrough) < 0) closedThrough = beforeOut;
    }
    var survived = 0;
    for (
      var day = firstJudged;
      day.compareTo(closedThrough) <= 0;
      day = addDaysToDayKey(day, 1)
    ) {
      if (made(day)) survived++;
    }

    // Once over, nothing after the last judged day belongs to the challenge.
    final settledEnd = isOver ? (lastEvaluated ?? lastDay ?? today) : null;

    StreakDay dayOf(String day) {
      StreakDayStatus status;
      var fraction = 0.0;
      if (day.compareTo(firstJudged) < 0) {
        status = StreakDayStatus.inactive;
      } else if (out != null && day == out) {
        status = StreakDayStatus.missed;
      } else if (out != null && day.compareTo(out) > 0) {
        status = StreakDayStatus.inactive;
      } else if (settledEnd != null && day.compareTo(settledEnd) > 0) {
        status = StreakDayStatus.inactive;
      } else if (day.compareTo(today) > 0) {
        status = StreakDayStatus.upcoming;
      } else if (day == today) {
        status = made(day) ? StreakDayStatus.todayMade : StreakDayStatus.today;
        fraction = minimum > 0
            ? ((daily[day] ?? 0) / minimum).clamp(0.0, 1.0)
            : 1.0;
      } else {
        status = made(day) ? StreakDayStatus.made : StreakDayStatus.missed;
      }
      return StreakDay(dayKey: day, status: status, todayFraction: fraction);
    }

    // The calendar runs from day 1 to the last day; with no end date, to the
    // end of the current week.
    int weekday(String day) => DateTime.parse('${day}T00:00:00Z').weekday % 7;
    String calendarEnd;
    if (lastDay != null) {
      calendarEnd = lastDay;
    } else if (isOver) {
      calendarEnd = lastEvaluated ?? today;
    } else {
      final anchor = today.compareTo(startDay) > 0 ? today : startDay;
      calendarEnd = addDaysToDayKey(anchor, 6 - weekday(anchor));
    }
    if (calendarEnd.compareTo(startDay) < 0) calendarEnd = startDay;

    final gridStart = addDaysToDayKey(startDay, -weekday(startDay));
    final gridEnd = addDaysToDayKey(calendarEnd, 6 - weekday(calendarEnd));
    final totalWeeks = (daysBetweenDayKeys(gridStart, gridEnd) + 1) ~/ 7;

    // Long challenges: show the weeks around today — with a week of
    // lookahead when there's room for it, otherwise the latest weeks.
    var firstWeek = 0;
    var lastWeek = totalWeeks - 1;
    if (totalWeeks > maxWeeks) {
      final focus = today.compareTo(startDay) < 0
          ? startDay
          : today.compareTo(calendarEnd) > 0
          ? calendarEnd
          : today;
      final focusWeek = daysBetweenDayKeys(gridStart, focus) ~/ 7;
      final lookahead = maxWeeks > 2 ? 1 : 0;
      lastWeek = math.min(
        totalWeeks - 1,
        math.max(focusWeek + lookahead, maxWeeks - 1),
      );
      firstWeek = lastWeek - (maxWeeks - 1);
    }

    final cells = <StreakDay?>[];
    for (var i = firstWeek * 7; i < (lastWeek + 1) * 7; i++) {
      final day = addDaysToDayKey(gridStart, i);
      final inRange =
          day.compareTo(startDay) >= 0 && day.compareTo(calendarEnd) <= 0;
      cells.add(inRange ? dayOf(day) : null);
    }

    final todayAmount = daily[today] ?? 0;
    final String caption;
    var captionPositive = false;
    if (out != null) {
      caption = 'Out on day ${daysBetweenDayKeys(startDay, out) + 1}';
    } else if (isOver) {
      caption = 'Challenge over';
    } else if (today.compareTo(startDay) < 0) {
      caption = 'Starts ${shortDayLabel(startDay)}';
    } else if (made(today)) {
      caption = 'Safe today ✓ · counts when the day ends';
      captionPositive = true;
    } else {
      caption =
          'Today: ${formatCount(todayAmount)} / ${formatCount(minimum)}$unitSuffix';
    }

    final totalDays = lastDay != null
        ? daysBetweenDayKeys(startDay, lastDay) + 1
        : null;

    return StreakProgress(
      ProgressHeadline(
        value: formatCount(survived),
        label: totalDays != null
            ? 'of $totalDays days survived'
            : survived == 1
            ? 'day survived'
            : 'days survived',
        caption: caption,
        captionPositive: captionPositive,
      ),
      cells: cells,
      hiddenWeeks: totalWeeks - (lastWeek - firstWeek + 1),
      survived: survived,
      totalDays: totalDays,
      todayAmount: todayAmount,
      minimum: minimum,
      outOnDay: out != null ? daysBetweenDayKeys(startDay, out) + 1 : null,
      startsOn: today.compareTo(startDay) < 0 ? startDay : null,
      isOver: isOver,
    );
  }
}

// ─────────────────────────────────────────────
// Glance ring — the Home card's one-ring summary, the same shape for every
// mode so the card can always pair it with the Aggressor Badge.
// ─────────────────────────────────────────────

/// One ring: how full it is and what's written inside it.
class GlanceRing {
  /// How full the ring is, 0..1.
  final double fraction;

  /// The big figure inside the ring, and the line under it.
  final String value;
  final String label;

  /// Good news: finished, safe today, leading. Drawn in the success colour.
  final bool achieved;

  /// Out of the running (eliminated). Drawn muted, figure in the error colour.
  final bool out;

  const GlanceRing({
    required this.fraction,
    required this.value,
    required this.label,
    this.achieved = false,
    this.out = false,
  });
}

/// The Home card's ring for [progress]: share of target (Race), today
/// against the daily minimum (Last One Standing), or total against the
/// leader's (Most Progress — the one that needs [participants]). Null for
/// a race with no usable target.
GlanceRing? glanceRingOf(
  Challenge challenge,
  PersonalProgress progress,
  Map<String, dynamic> me,
  List<Map<String, dynamic>> participants,
) {
  switch (progress) {
    case RaceProgress race:
      return GlanceRing(
        fraction: race.fraction,
        value: race.headline.value,
        label: '${formatCount(race.progress)} / ${formatCount(race.target)}',
        achieved: race.nextMilestone == null,
      );

    case StreakProgress streak:
      final outOnDay = streak.outOnDay;
      if (outOnDay != null) {
        return GlanceRing(
          fraction: 0,
          value: 'OUT',
          label: 'on day $outOnDay',
          out: true,
        );
      }
      final startsOn = streak.startsOn;
      if (startsOn != null) {
        return GlanceRing(
          fraction: 0,
          value: '–',
          label: 'starts ${shortDayLabel(startsOn)}',
        );
      }
      if (streak.isOver) {
        return GlanceRing(
          fraction: streak.totalDays != null && streak.totalDays! > 0
              ? (streak.survived / streak.totalDays!).clamp(0.0, 1.0)
              : 1,
          value: formatCount(streak.survived),
          label: 'survived',
          achieved: true,
        );
      }
      final safe = streak.minimum <= 0 || streak.todayAmount >= streak.minimum;
      return GlanceRing(
        fraction: streak.minimum > 0
            ? (streak.todayAmount / streak.minimum).clamp(0.0, 1.0)
            : 1,
        value:
            '${formatCount(streak.todayAmount)}/${formatCount(streak.minimum)}',
        label: safe ? 'safe today ✓' : 'today',
        achieved: safe,
      );

    case GrowthProgress growth:
      final uid = me['uid'];
      final total = _progressOf(me);
      final others = [
        for (final p in participants)
          if (p['uid'] != uid) _progressOf(p),
      ];
      final leaderTotal = others.fold<int>(total, math.max);
      final rank = 1 + others.where((other) => other > total).length;
      // A rank means nothing until someone has logged something.
      final ranked = others.isNotEmpty && leaderTotal > 0;

      return GlanceRing(
        fraction: leaderTotal > 0 ? total / leaderTotal : 0,
        value: growth.headline.value,
        label: ranked
            ? '${growth.headline.label} · #$rank'
            : growth.headline.label,
        achieved: total > 0 && rank == 1,
      );

    case TotalOnlyProgress():
      return null;
  }
}

PersonalProgress _raceOf(Challenge challenge, Map<String, dynamic> me) {
  final progress = _progressOf(me);
  final unit = _unitOf(challenge, me);
  final unitSuffix = unit.isNotEmpty ? ' $unit' : '';
  final target = challenge.targetFor(me);

  if (target == null) {
    return TotalOnlyProgress(
      ProgressHeadline(
        value: formatCount(progress),
        label: unit.isNotEmpty ? unit : 'total',
      ),
    );
  }

  final finished = progress >= target;
  return RaceProgress(
    ProgressHeadline(
      value: '${math.min(percentOf(progress, target), 100)}%',
      label: 'complete',
      caption:
          '${formatCount(progress)} / ${formatCount(target)}$unitSuffix'
          '${finished ? ' · Finished' : ''}',
      captionPositive: finished,
    ),
    progress: progress,
    target: target,
  );
}

int _progressOf(Map<String, dynamic> me) =>
    math.max(0, (me['progress'] as num? ?? 0).toInt());

String _unitOf(Challenge challenge, Map<String, dynamic> me) {
  final unit = (me['unit'] ?? '').toString();
  return unit.isNotEmpty ? unit : challenge.unit;
}

Map<String, int> _dailyOf(Map<String, dynamic> me) {
  final raw = me['dailyProgress'] as Map<String, dynamic>? ?? const {};
  return {
    for (final entry in raw.entries)
      if (entry.value is num) entry.key: (entry.value as num).toInt(),
  };
}

/// The challenge day [me] joined on; null while the server timestamp of a
/// fresh join is still pending.
String? _joinedDay(Challenge challenge, Map<String, dynamic> me) {
  final joinedAt = me['joinedAt'] as Timestamp?;
  return joinedAt == null ? null : challenge.dayKey(joinedAt.toDate());
}

/// The last challenge day before [endsAt] (which is the start of the day
/// after it).
String _lastDayOf(Challenge challenge, DateTime endsAt) =>
    challenge.dayKey(endsAt.subtract(const Duration(milliseconds: 1)));
