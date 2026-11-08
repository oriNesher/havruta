import 'package:cloud_firestore/cloud_firestore.dart';

import 'challenge.dart';

/// Client-side mirror of the Aggressor Badge's scoring, for display only —
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

/// One participant's standing for the badge. Mirrors AggressorScore.
class AggressorScore {
  final String uid;
  final String username;

  /// Progress logged across their eligible window days.
  final int windowTotal;

  /// Window days on or after both the day they joined and the challenge's
  /// first day; never less than 1.
  final int eligibleDays;

  const AggressorScore({
    required this.uid,
    required this.username,
    required this.windowTotal,
    required this.eligibleDays,
  });
}

/// Scores [participant] for the badge. Mirrors scoreAggressor.
AggressorScore scoreAggressor(
  Challenge challenge,
  Map<String, dynamic> participant,
  DateTime now,
) {
  final daily = participant['dailyProgress'] as Map<String, dynamic>? ?? {};
  final joinedAt = (participant['joinedAt'] as Timestamp?)?.toDate();
  final joinedDay = joinedAt == null ? null : challenge.dayKey(joinedAt);
  final startsAt = challenge.startsAt;
  final startDay = startsAt == null ? null : challenge.dayKey(startsAt);

  final eligible = aggressorWindow(challenge, now).where(
    (day) =>
        (joinedDay == null || joinedDay.compareTo(day) <= 0) &&
        (startDay == null || startDay.compareTo(day) <= 0),
  );
  var total = 0;
  for (final day in eligible) {
    final amount = (daily[day] as num? ?? 0).toInt();
    if (amount > 0) total += amount;
  }

  final uid = participant['uid'] as String? ?? '';
  return AggressorScore(
    uid: uid,
    username: participant['username'] as String? ?? uid,
    windowTotal: total,
    eligibleDays: eligible.isEmpty ? 1 : eligible.length,
  );
}

/// What [participant] has logged across the badge's window — the "last 3
/// days" figure shown next to the badge.
int aggressorWindowTotal(
  Challenge challenge,
  Map<String, dynamic> participant,
  DateTime now,
) => scoreAggressor(challenge, participant, now).windowTotal;

/// How much [challenger] must log (in their own days) to strictly overtake
/// [holder]'s rate — a tie keeps the holder, so matching isn't enough.
/// Mirrors compareAggressorRate: (P + x) / d_c > P_h / d_h.
int _amountToOvertake(AggressorScore challenger, AggressorScore holder) {
  final matching =
      holder.windowTotal * challenger.eligibleDays ~/ holder.eligibleDays;
  return matching - challenger.windowTotal + 1;
}

/// Where the viewer stands relative to the badge, for the Home card's
/// Aggressor section.
class AggressorStanding {
  /// The holder's name; null while the badge is vacant.
  final String? holderUsername;

  /// What the holder has logged across the window. Null while the badge is
  /// vacant, or when the holder is out of the running or has left.
  final int? holderTotal;
  final bool viewerHolds;

  /// The viewer can't hold the badge any more (eliminated).
  final bool viewerOut;

  /// Fewer than 2 participants: the server awards no badge until someone
  /// else joins, however much the viewer logs. Mirrors decideAggressor.
  final bool needsRival;

  /// Not the holder: how much more the viewer must log to take the badge
  /// (1 when it's vacant — any progress claims it).
  final int? toTake;

  /// The holder: how far ahead of the closest rival they are — that rival
  /// needs one more than this to take it — and who that rival is. Null
  /// when nobody else can hold it.
  final int? lead;
  final String? closestUsername;

  const AggressorStanding({
    required this.holderUsername,
    this.holderTotal,
    required this.viewerHolds,
    this.viewerOut = false,
    this.needsRival = false,
    this.toTake,
    this.lead,
    this.closestUsername,
  });
}

/// Works out [viewerUid]'s [AggressorStanding] from everyone's window
/// scores. The server decides who holds the badge; this only measures the
/// distance to it, so a holder the server hasn't re-decided yet (e.g. just
/// after midnight) shows a distance of at least 1 rather than a negative.
AggressorStanding aggressorStanding(
  Challenge challenge,
  List<Map<String, dynamic>> participants,
  String viewerUid,
  DateTime now,
) {
  final contenders = participants
      .where((p) => p['uid'] is String && p['eliminatedOnDay'] == null)
      .map((p) => scoreAggressor(challenge, p, now))
      .toList();
  final holderUid = challenge.aggressorUid;
  final holder = contenders.where((s) => s.uid == holderUid).firstOrNull;
  final holderUsername = holderUid == null
      ? null
      : holder?.username ?? challenge.aggressorUsername ?? 'Someone';
  final holderTotal = holder?.windowTotal;
  final viewer = contenders.where((s) => s.uid == viewerUid).firstOrNull;

  if (participants.where((p) => p['uid'] is String).length < 2) {
    return AggressorStanding(
      holderUsername: holderUsername,
      holderTotal: holderTotal,
      viewerHolds: holderUid == viewerUid,
      needsRival: true,
    );
  }

  if (viewer == null) {
    return AggressorStanding(
      holderUsername: holderUsername,
      holderTotal: holderTotal,
      viewerHolds: false,
      viewerOut: true,
    );
  }

  if (holderUid == viewerUid) {
    // Closest = whoever needs the least to take it, which isn't always the
    // best rate: a late joiner's amount counts over fewer days.
    AggressorScore? closest;
    int? closestNeeds;
    for (final rival in contenders.where((s) => s.uid != viewerUid)) {
      final needs = _amountToOvertake(rival, viewer);
      if (closestNeeds == null || needs < closestNeeds) {
        closest = rival;
        closestNeeds = needs;
      }
    }
    if (closest == null || closestNeeds == null) {
      return AggressorStanding(
        holderUsername: holderUsername,
        holderTotal: holderTotal,
        viewerHolds: true,
      );
    }
    final lead = closestNeeds - 1;
    return AggressorStanding(
      holderUsername: holderUsername,
      holderTotal: holderTotal,
      viewerHolds: true,
      lead: lead < 0 ? 0 : lead,
      closestUsername: closest.username,
    );
  }

  final toTake = holder == null ? 1 : _amountToOvertake(viewer, holder);
  return AggressorStanding(
    holderUsername: holderUsername,
    holderTotal: holderTotal,
    viewerHolds: false,
    toTake: toTake < 1 ? 1 : toTake,
  );
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
