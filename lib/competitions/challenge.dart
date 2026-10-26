import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// How a challenge's winner is decided. Stored as `competition.winCondition`
/// by [WinCondition.name]; a document without one predates win conditions
/// and is a race. Hand-synced with WIN_CONDITIONS in
/// functions/src/challenges/model.ts.
enum WinCondition {
  /// First to reach the shared target wins.
  firstToTarget,

  /// Everyone must meet a daily minimum; missing a day eliminates you, and
  /// the last one left wins.
  lastStanding,

  /// Most total progress when the challenge ends wins.
  mostProgress;

  static WinCondition? tryParse(Object? value) {
    for (final condition in values) {
      if (condition.name == value) return condition;
    }
    return null;
  }

  /// User-facing mode name.
  String get label => switch (this) {
    WinCondition.firstToTarget => 'Race',
    WinCondition.lastStanding => 'Last One Standing',
    WinCondition.mostProgress => 'Most Progress',
  };

  /// One-line explanation of how this mode is won.
  String get tagline => switch (this) {
    WinCondition.firstToTarget => 'First to reach the target wins.',
    WinCondition.lastStanding =>
      'Hit the daily minimum every day. Miss one and you\'re out — last one left wins.',
    WinCondition.mostProgress => 'Most progress by the end date wins.',
  };
}

/// Extra constraints layered on top of the win condition.
class ChallengeRules {
  /// Minimum progress per challenge day. Required for
  /// [WinCondition.lastStanding]; null when there's no daily requirement.
  final int? dailyMinimum;

  /// Missed days absorbed before elimination. Reserved for grace days —
  /// always 0 until that rule exists.
  final int lives;

  const ChallengeRules({this.dailyMinimum, this.lives = 0});

  factory ChallengeRules.fromMap(Map<String, dynamic>? map) {
    return ChallengeRules(
      dailyMinimum: _positiveIntOrNull(map?['dailyMinimum']),
      lives: _positiveIntOrNull(map?['lives']) ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    if (dailyMinimum != null) 'dailyMinimum': dailyMinimum,
  };
}

/// A competitions/{id} document read as a challenge definition. The one
/// place the client interprets the raw `type` / `shared*` fields, so
/// legacy documents and new ones look the same past this point.
class Challenge {
  final String id;
  final String title;
  final String description;
  final String createdBy;
  final String status;

  final WinCondition winCondition;

  /// A pre-redesign Personal Goal challenge: still a race, but each
  /// participant races to their own participants/{uid}.targetValue.
  final bool isLegacyPersonal;

  final String goalTitle;
  final String unit;

  /// The race's finish line; null for the other modes (and for legacy
  /// personal challenges, whose targets live on each participant).
  final int? targetValue;

  final ChallengeRules rules;

  /// What the winner gets, free text (e.g. "Loser buys pizza"); null when
  /// the creator didn't set one. Display only.
  final String? prize;

  /// IANA zone whose calendar defines challenge days; null means UTC.
  final String? timeZone;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// Free-text deadline from before [endsAt] existed. Display only.
  final String? legacyDeadline;

  final List<String> winnerUids;

  /// Last challenge day (YYYY-MM-DD) the server has judged a Last One
  /// Standing challenge through; null until judging starts.
  final String? lastEvaluatedDay;

  const Challenge({
    required this.id,
    required this.title,
    this.description = '',
    required this.createdBy,
    this.status = 'active',
    this.winCondition = WinCondition.firstToTarget,
    this.isLegacyPersonal = false,
    this.goalTitle = '',
    this.unit = '',
    this.targetValue,
    this.rules = const ChallengeRules(),
    this.prize,
    this.timeZone,
    this.startsAt,
    this.endsAt,
    this.legacyDeadline,
    this.winnerUids = const [],
    this.lastEvaluatedDay,
  });

  factory Challenge.fromDoc(String id, Map<String, dynamic> data) {
    final winCondition =
        WinCondition.tryParse(data['winCondition']) ??
        WinCondition.firstToTarget;
    final winnerUids = (data['winnerUids'] as List?)?.whereType<String>()
        .toList();
    final legacyWinner = data['winnerUid'] as String?;

    return Challenge(
      id: id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
      status: data['status'] as String? ?? 'active',
      winCondition: winCondition,
      // Only documents written before win conditions can be personal; new
      // challenges always carry a winCondition.
      isLegacyPersonal:
          data['winCondition'] == null &&
          data['type'] == 'personalGoalChallenge',
      goalTitle: data['sharedGoalTitle'] as String? ?? '',
      unit: data['sharedUnit'] as String? ?? '',
      targetValue: winCondition == WinCondition.firstToTarget
          ? _positiveIntOrNull(data['sharedTargetValue'])
          : null,
      rules: ChallengeRules.fromMap(data['rules'] as Map<String, dynamic>?),
      prize: (data['prize'] as String?)?.trim().isNotEmpty == true
          ? (data['prize'] as String).trim()
          : null,
      timeZone: (data['timeZone'] as String?)?.isNotEmpty == true
          ? data['timeZone'] as String
          : null,
      startsAt: (data['startsAt'] as Timestamp?)?.toDate(),
      endsAt: (data['endsAt'] as Timestamp?)?.toDate(),
      legacyDeadline: data['deadline'] as String?,
      winnerUids: winnerUids != null && winnerUids.isNotEmpty
          ? winnerUids
          : [?legacyWinner],
      lastEvaluatedDay: data['lastEvaluatedDay'] as String?,
    );
  }

  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';

  /// User-facing mode name, e.g. for the details badge.
  String get modeLabel =>
      isLegacyPersonal ? 'Personal Goal Challenge' : winCondition.label;

  /// Whether this challenge measures progress as a share of a target
  /// (percent bars, "x / y"), as opposed to raw totals.
  bool get hasTarget => winCondition == WinCondition.firstToTarget;

  /// The finish line [participant] is racing to, or null when this
  /// challenge has none.
  int? targetFor(Map<String, dynamic> participant) {
    if (!hasTarget) return null;
    return _positiveIntOrNull(participant['targetValue']) ?? targetValue;
  }

  /// "30 km" / "30" — the goal's target with its unit, if any.
  String? get targetLabel {
    final target = targetValue;
    if (target == null) return null;
    return unit.isNotEmpty ? '$target $unit' : '$target';
  }

  /// Short description of what the goal is, for invites and headers:
  /// "Run — 100 km", "Study — at least 30 min a day", "Read (pages)".
  String get goalSummary {
    final minimum = rules.dailyMinimum;
    final unitSuffix = unit.isNotEmpty ? ' $unit' : '';
    return switch (winCondition) {
      WinCondition.firstToTarget when targetLabel != null =>
        '$goalTitle — $targetLabel',
      WinCondition.lastStanding when minimum != null =>
        '$goalTitle — at least $minimum$unitSuffix a day',
      _ => unit.isNotEmpty ? '$goalTitle ($unit)' : goalTitle,
    };
  }

  /// The challenge-calendar date (YYYY-MM-DD) [moment] falls on. Every
  /// participant shares this calendar, wherever they are — it's the key for
  /// participants/{uid}.dailyProgress and what Last One Standing judges.
  /// Must agree with challengeDayKey in functions/src/challenges/calendar.ts.
  String dayKey(DateTime moment) {
    final local = _inChallengeZone(moment);
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  /// When the challenge-calendar day containing [moment] ends.
  DateTime endOfDay(DateTime moment) {
    final local = _inChallengeZone(moment);
    final zone = timeZone;
    if (zone == null) {
      return DateTime.utc(local.year, local.month, local.day + 1);
    }
    return tz.TZDateTime(
      _location(zone),
      local.year,
      local.month,
      local.day + 1,
    );
  }

  DateTime _inChallengeZone(DateTime moment) {
    final zone = timeZone;
    if (zone == null) return moment.toUtc();
    return tz.TZDateTime.from(moment, _location(zone));
  }

  static bool _tzInitialized = false;

  static tz.Location _location(String name) {
    if (!_tzInitialized) {
      tzdata.initializeTimeZones();
      _tzInitialized = true;
    }
    try {
      return tz.getLocation(name);
    } on tz.LocationNotFoundException {
      return tz.UTC;
    }
  }
}

/// Shifts a YYYY-MM-DD challenge day by whole [days]. Pure date arithmetic,
/// so DST never shifts it. Mirrors addDays in
/// functions/src/challenges/calendar.ts.
String addDaysToDayKey(String dayKey, int days) {
  final shifted = DateTime.parse('${dayKey}T00:00:00Z').add(
    Duration(days: days),
  );
  return shifted.toIso8601String().substring(0, 10);
}

/// Whole days from challenge day [a] to [b] (b - a). Mirrors daysBetween in
/// functions/src/challenges/calendar.ts.
int daysBetweenDayKeys(String a, String b) => DateTime.parse(
  '${b}T00:00:00Z',
).difference(DateTime.parse('${a}T00:00:00Z')).inDays;

int? _positiveIntOrNull(Object? value) {
  final number = (value as num?)?.toInt();
  return number != null && number > 0 ? number : null;
}
