import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../challenge.dart';
import '../personal_progress.dart';

/// The Challenge Details "Your progress" page: a big headline number and the
/// viewer's own progress drawn for the challenge's mode — a milestone ring
/// for a race, a growth curve for Most Progress, a streak calendar for Last
/// One Standing. Personal only; comparing is the leaderboard's job.
class PersonalProgressPanel extends StatelessWidget {
  final Challenge challenge;

  /// The viewer's raw participants/{uid} doc.
  final Map<String, dynamic> me;

  /// The Home card's version: the same view scaled down, with no heading or
  /// frame of its own, and the calendar trimmed to the last two weeks.
  final bool compact;

  const PersonalProgressPanel({
    super.key,
    required this.challenge,
    required this.me,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = PersonalProgress.of(
      challenge,
      me,
      maxCalendarWeeks: compact ? 2 : 6,
    );
    final gap = EdgeInsets.only(top: compact ? 14 : 20);

    // The Home card's race view sits the percentage beside the ring instead
    // of above it — the card is short on height, not width.
    if (compact && progress is RaceProgress) {
      return Row(
        children: [
          Expanded(
            child: _Headline(headline: progress.headline, compact: compact),
          ),
          const SizedBox(width: 16),
          _MilestoneRing(progress: progress, compact: compact),
        ],
      );
    }

    final body = Column(
      // Its own height whatever it's placed in — the Home carousel sizes
      // itself from this.
      mainAxisSize: MainAxisSize.min,
      children: [
        _Headline(headline: progress.headline, compact: compact),
        switch (progress) {
          RaceProgress race => Padding(
            padding: gap,
            child: _MilestoneRing(progress: race, compact: compact),
          ),
          GrowthProgress growth => Padding(
            padding: gap,
            child: _GrowthCurve(progress: growth, compact: compact),
          ),
          StreakProgress streak => Padding(
            padding: gap,
            child: _StreakCalendar(progress: streak, compact: compact),
          ),
          TotalOnlyProgress() => const SizedBox.shrink(),
        },
      ],
    );
    if (compact) return body;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your progress', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor),
          ),
          child: body,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Headline — the one number this page is about
// ─────────────────────────────────────────────

class _Headline extends StatelessWidget {
  final ProgressHeadline headline;
  final bool compact;

  const _Headline({required this.headline, required this.compact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final positive = theme.colorScheme.tertiary;

    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            headline.value,
            maxLines: 1,
            style: AppTheme.mono(
              fontSize: compact ? 36 : 56,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        Text(
          headline.label,
          textAlign: TextAlign.center,
          style: AppTheme.display(
            fontSize: compact ? 15 : 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: muted,
          ),
        ),
        if (headline.caption.isNotEmpty) ...[
          SizedBox(height: compact ? 6 : 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: headline.captionPositive
                ? BoxDecoration(
                    color: positive.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  )
                : null,
            child: Text(
              headline.caption,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: headline.captionPositive ? positive : muted,
                fontWeight: headline.captionPositive ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Race — milestone ring
// ─────────────────────────────────────────────

class _MilestoneRing extends StatelessWidget {
  final RaceProgress progress;
  final bool compact;

  const _MilestoneRing({required this.progress, required this.compact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = progress.nextMilestone;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = compact
            ? math.min(constraints.maxWidth * 0.45, 120.0)
            : math.min(constraints.maxWidth * 0.6, 220.0);
        return SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _MilestoneRingPainter(
              fraction: progress.fraction,
              trackColor: theme.colorScheme.surfaceContainerHighest,
              doneColor: theme.colorScheme.tertiary,
              currentColor: theme.colorScheme.primary,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    next == null ? 'FINISHED' : 'NEXT',
                    style: AppTheme.display(
                      fontSize: compact ? 11 : 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: next == null
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  if (next != null)
                    Text(
                      '$next%',
                      style: AppTheme.mono(
                        fontSize: compact ? 16 : 22,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One arc per milestone stretch (0–25, 25–50, 50–75, 75–90, 90–100%):
/// finished stretches in [doneColor], the current one filling in
/// [currentColor], the rest as a faint track.
class _MilestoneRingPainter extends CustomPainter {
  final double fraction;
  final Color trackColor;
  final Color doneColor;
  final Color currentColor;

  _MilestoneRingPainter({
    required this.fraction,
    required this.trackColor,
    required this.doneColor,
    required this.currentColor,
  });

  static const double _gap = 0.06; // radians between segments

  @override
  void paint(Canvas canvas, Size size) {
    // ~14px on the full-size ring, thinner as it shrinks.
    final stroke = math.max(8.0, size.shortestSide * 0.064);
    final radius = size.shortestSide / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: radius);
    final marks = [0, ...kRaceMilestones, 100].map((m) => m / 100).toList();
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    for (var i = 0; i < marks.length - 1; i++) {
      final from = marks[i];
      final to = marks[i + 1];
      final start = -math.pi / 2 + from * 2 * math.pi + _gap / 2;
      final sweep = (to - from) * 2 * math.pi - _gap;

      canvas.drawArc(rect, start, sweep, false, arc(trackColor));
      if (fraction >= to) {
        canvas.drawArc(rect, start, sweep, false, arc(doneColor));
      } else if (fraction > from) {
        final share = (fraction - from) / (to - from);
        canvas.drawArc(rect, start, sweep * share, false, arc(currentColor));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MilestoneRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.doneColor != doneColor ||
      oldDelegate.currentColor != currentColor;
}

// ─────────────────────────────────────────────
// Most Progress — growth curve
// ─────────────────────────────────────────────

class _GrowthCurve extends StatelessWidget {
  final GrowthProgress progress;
  final bool compact;

  const _GrowthCurve({required this.progress, required this.compact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(fontSize: 10) ??
        const TextStyle(fontSize: 10);
    final nothingYet = progress.totals.last == 0 && !progress.isOver;

    return SizedBox(
      height: compact ? 110 : 170,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GrowthCurvePainter(
                progress: progress,
                lineColor: theme.colorScheme.primary,
                baselineColor: theme.dividerColor,
                dotRingColor: theme.colorScheme.surface,
                labelStyle: labelStyle,
                maxLabelStyle: AppTheme.mono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          if (nothingYet)
            Center(
              child: Text(
                'Log your first progress',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Running total over the challenge's timeline. Days still ahead stay empty
/// (a dashed baseline to the end date). On a long timeline with little of
/// it gone, the elapsed stretch is given at least [_minElapsedShare] of the
/// width so the curve stays readable, and a break mark shows where the
/// compressed future begins.
class _GrowthCurvePainter extends CustomPainter {
  final GrowthProgress progress;
  final Color lineColor;
  final Color baselineColor;
  final Color dotRingColor;
  final TextStyle labelStyle;
  final TextStyle maxLabelStyle;

  _GrowthCurvePainter({
    required this.progress,
    required this.lineColor,
    required this.baselineColor,
    required this.dotRingColor,
    required this.labelStyle,
    required this.maxLabelStyle,
  });

  static const double _minElapsedShare = 0.6;

  /// Each elapsed day earns at least this share of the width, up to
  /// [_minElapsedShare] — so day 2 isn't stretched across half the chart.
  static const double _perDayShare = 0.12;

  @override
  void paint(Canvas canvas, Size size) {
    final totals = progress.totals;
    final plot = Rect.fromLTRB(6, 20, size.width - 6, size.height - 22);
    final elapsedSteps = totals.length - 1;
    final allSteps = progress.totalDays - 1;

    final linearShare = allSteps == 0 ? 1.0 : elapsedSteps / allSteps;
    final elapsedShare = progress.hasFuture
        ? math.max(
            linearShare,
            math.min(_minElapsedShare, elapsedSteps * _perDayShare),
          )
        : 1.0;
    final compressed = elapsedShare > linearShare + 0.001;
    final todayX = plot.left + plot.width * elapsedShare;
    double xFor(int i) => elapsedSteps == 0
        ? plot.left
        : plot.left + (todayX - plot.left) * i / elapsedSteps;

    final maxValue = math.max(totals.reduce(math.max), 1);
    double yFor(int value) =>
        plot.bottom - plot.height * (value.clamp(0, maxValue) / maxValue);

    // Baseline: solid through today, dashed across the days still ahead.
    final baseline = Paint()
      ..color = baselineColor
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(progress.hasFuture ? todayX : plot.right, plot.bottom),
      baseline,
    );
    if (progress.hasFuture) {
      for (var x = todayX + 4; x < plot.right; x += 8) {
        canvas.drawLine(
          Offset(x, plot.bottom),
          Offset(math.min(x + 4, plot.right), plot.bottom),
          baseline,
        );
      }
      // End-of-challenge tick.
      canvas.drawLine(
        Offset(plot.right, plot.bottom - 5),
        Offset(plot.right, plot.bottom + 3),
        baseline,
      );
      if (compressed) {
        final breakX = todayX + 10;
        for (final dx in [-2.5, 2.5]) {
          canvas.drawLine(
            Offset(breakX + dx - 2.5, plot.bottom + 4),
            Offset(breakX + dx + 2.5, plot.bottom - 4),
            baseline,
          );
        }
      }
    }

    // Area and line.
    final points = [
      for (var i = 0; i < totals.length; i++) Offset(xFor(i), yFor(totals[i])),
    ];
    if (points.length > 1) {
      final area = Path()..moveTo(points.first.dx, plot.bottom);
      for (final p in points) {
        area.lineTo(p.dx, p.dy);
      }
      area
        ..lineTo(points.last.dx, plot.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              lineColor.withValues(alpha: 0.32),
              lineColor.withValues(alpha: 0.02),
            ],
          ).createShader(plot),
      );

      final line = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        line.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        line,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(points.last, 6, Paint()..color = dotRingColor);
    canvas.drawCircle(points.last, 4, Paint()..color = lineColor);

    // Labels: the top value, then dates along the bottom.
    final unitSuffix = progress.unit.isNotEmpty ? ' ${progress.unit}' : '';
    // maxValue is floored at 1 to keep the scale finite; don't label that.
    if (totals.any((total) => total > 0)) {
      _text('${formatCount(maxValue)}$unitSuffix', maxLabelStyle)
          .paint(canvas, Offset(plot.left, 0));
    }

    final labelY = plot.bottom + 6;
    final start = _text(shortDayLabel(progress.startDay), labelStyle);
    final startRect = Offset(plot.left, labelY) & start.size;
    start.paint(canvas, startRect.topLeft);

    final end = _text(
      progress.hasFuture || progress.isOver
          ? shortDayLabel(progress.lastDay)
          : 'Today',
      labelStyle,
    );
    final endRect = Offset(plot.right - end.width, labelY) & end.size;
    if (!endRect.overlaps(startRect.inflate(4))) end.paint(canvas, endRect.topLeft);

    if (progress.hasFuture) {
      final today = _text('Today', labelStyle);
      final todayRect =
          Offset(todayX - today.width / 2, labelY) & today.size;
      if (!todayRect.overlaps(startRect.inflate(4)) &&
          !todayRect.overlaps(endRect.inflate(4))) {
        today.paint(canvas, todayRect.topLeft);
      }

      final daysLeft = progress.totalDays - totals.length;
      final toGo = _text(
        daysLeft == 1 ? '1 day to go' : '${formatCount(daysLeft)} days to go',
        labelStyle,
      );
      final zoneLeft = todayX + 16;
      if (plot.right - zoneLeft > toGo.width + 8) {
        toGo.paint(
          canvas,
          Offset(
            (zoneLeft + plot.right - toGo.width) / 2,
            plot.bottom - toGo.height - 6,
          ),
        );
      }
    }
  }

  TextPainter _text(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  // Rebuilt from a fresh GrowthProgress on every stream update; cheap enough
  // to always repaint.
  @override
  bool shouldRepaint(covariant _GrowthCurvePainter oldDelegate) => true;
}

// ─────────────────────────────────────────────
// Last One Standing — streak calendar
// ─────────────────────────────────────────────

const List<String> _weekdayInitials = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

class _StreakCalendar extends StatelessWidget {
  final StreakProgress progress;
  final bool compact;

  const _StreakCalendar({required this.progress, required this.compact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(fontSize: 10);
    final gap = compact ? 5.0 : 6.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = ((constraints.maxWidth - gap * 6) / 7).clamp(
          18.0,
          compact ? 28.0 : 40.0,
        );
        final rows = progress.cells.length ~/ 7;

        Widget row(List<Widget> children) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              children[i],
            ],
          ],
        );

        return Column(
          children: [
            row([
              for (final initial in _weekdayInitials)
                SizedBox(
                  width: cell,
                  child: Text(initial, textAlign: TextAlign.center, style: labelStyle),
                ),
            ]),
            const SizedBox(height: 6),
            for (var r = 0; r < rows; r++)
              Padding(
                padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : gap),
                child: row([
                  for (final day in progress.cells.sublist(r * 7, r * 7 + 7))
                    _StreakCell(day: day, size: cell),
                ]),
              ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 4,
              children: [
                _LegendItem(status: StreakDayStatus.made, label: 'Made it'),
                _LegendItem(status: StreakDayStatus.missed, label: 'Missed'),
                _LegendItem(status: StreakDayStatus.today, label: 'Today'),
                if (progress.hiddenWeeks > 0)
                  Text(
                    'Showing ${progress.shownWeeks} of '
                    '${progress.shownWeeks + progress.hiddenWeeks} weeks',
                    style: labelStyle,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _StreakCell extends StatelessWidget {
  final StreakDay? day;
  final double size;

  const _StreakCell({required this.day, required this.size});

  @override
  Widget build(BuildContext context) {
    final day = this.day;
    if (day == null) return SizedBox.square(dimension: size);

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(size * 0.28);
    final numberStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: (size * 0.32).clamp(9.0, 12.0),
    );
    // Legend swatches are too small to carry a date.
    Widget number([Color? color]) => size < 16
        ? const SizedBox.shrink()
        : Text('${day.dayOfMonth}', style: numberStyle?.copyWith(color: color));
    final check = Icon(Icons.check_rounded, size: size * 0.6, color: scheme.surface);

    final (decoration, child) = switch (day.status) {
      StreakDayStatus.made => (
        BoxDecoration(color: scheme.tertiary, borderRadius: radius),
        check,
      ),
      // Safe already, so it looks made — with today's outline, since it
      // only counts as survived once the day ends.
      StreakDayStatus.todayMade => (
        BoxDecoration(
          color: scheme.tertiary,
          borderRadius: radius,
          border: Border.all(color: scheme.onSurface, width: 2),
        ),
        check,
      ),
      StreakDayStatus.missed => (
        BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: scheme.error, width: 1.5),
        ),
        Icon(Icons.close_rounded, size: size * 0.55, color: scheme.error),
      ),
      StreakDayStatus.today => (
        BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: scheme.onSurface, width: 1.5),
        ),
        Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: day.todayFraction,
                widthFactor: 1,
                child: ColoredBox(
                  color: scheme.tertiary.withValues(alpha: 0.45),
                ),
              ),
            ),
            Center(child: number(scheme.onSurface)),
          ],
        ),
      ),
      StreakDayStatus.upcoming => (
        BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: theme.dividerColor),
        ),
        number(),
      ),
      StreakDayStatus.inactive => (
        BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: radius,
        ),
        number(scheme.onSurface.withValues(alpha: 0.25)),
      ),
    };

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: decoration,
      child: child,
    );
  }
}

class _LegendItem extends StatelessWidget {
  final StreakDayStatus status;
  final String label;

  const _LegendItem({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StreakCell(
          day: StreakDay(dayKey: '2000-01-01', status: status),
          size: 12,
        ),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(fontSize: 10)),
      ],
    );
  }
}
