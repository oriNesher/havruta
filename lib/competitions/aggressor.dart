import 'challenge.dart';

/// Client-side mirror of the Aggressor Badge's window, for display only —
/// who holds the badge is always the server's call (Challenge.aggressorUid).
/// Hand-synced with functions/src/challenges/aggressor.ts.

/// How many challenge days (today included) the badge looks back over.
/// Mirrors AGGRESSOR_WINDOW_DAYS.
const int kAggressorWindowDays = 3;

/// The challenge days the badge currently looks at, newest first. Mirrors
/// aggressorWindow.
List<String> aggressorWindow(Challenge challenge, DateTime now) {
  final today = challenge.dayKey(now);
  return [
    for (var back = 0; back < kAggressorWindowDays; back++)
      addDaysToDayKey(today, -back),
  ];
}

/// What [participant] has logged across the badge's window — the "last 3
/// days" figure shown next to the badge. Days before they joined or the
/// challenge started have no progress, so a plain sum matches the server's
/// windowTotal.
int aggressorWindowTotal(
  Challenge challenge,
  Map<String, dynamic> participant,
  DateTime now,
) {
  final daily = participant['dailyProgress'] as Map<String, dynamic>? ?? {};
  var total = 0;
  for (final day in aggressorWindow(challenge, now)) {
    final amount = (daily[day] as num? ?? 0).toInt();
    if (amount > 0) total += amount;
  }
  return total;
}

/// How much of a [reduction] to take off each window day's dailyProgress
/// bucket, most recent first — so taking progress back also takes it out
/// of the badge's window instead of leaving yesterday's logged amount
/// counting. Last One Standing has already judged past days, so there
/// only today can be reduced.
Map<String, int> windowDayReductions(
  Challenge challenge,
  Map<String, dynamic> participant,
  int reduction,
  DateTime now,
) {
  final daily = participant['dailyProgress'] as Map<String, dynamic>? ?? {};
  final days = challenge.winCondition == WinCondition.lastStanding
      ? [challenge.dayKey(now)]
      : aggressorWindow(challenge, now);
  final reductions = <String, int>{};
  var remaining = reduction;
  for (final day in days) {
    if (remaining <= 0) break;
    final logged = (daily[day] as num? ?? 0).toInt();
    final cut = remaining < logged ? remaining : logged;
    if (cut > 0) {
      reductions[day] = cut;
      remaining -= cut;
    }
  }
  return reductions;
}
