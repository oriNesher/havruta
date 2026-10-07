import 'package:cloud_firestore/cloud_firestore.dart';

import 'challenge.dart';

/// Ranks participants docs for [challenge]'s win condition, leader first.
/// The home card, details screen and activity graph all order by this, so
/// "who's winning" reads the same everywhere. Mirrors the server's
/// standings in functions/src/challenges/standings.ts.
///
/// - Race: share of target reached (each participant's own target for a
///   legacy personal challenge).
/// - Most Progress: raw total; a tie goes to whoever got there first.
/// - Last One Standing: still-in before eliminated, later eliminations
///   ahead of earlier ones, then total progress.
List<Map<String, dynamic>> rankParticipants(
  Challenge challenge,
  Iterable<Map<String, dynamic>> participants,
) {
  final ranked = participants.toList();
  ranked.sort((a, b) => _compare(challenge, a, b));
  return ranked;
}

/// Progress as a 0+ share of [participant]'s target, or null when the
/// challenge has no target (Most Progress, Last One Standing).
double? progressFraction(
  Challenge challenge,
  Map<String, dynamic> participant,
) {
  final target = challenge.targetFor(participant);
  if (target == null) return null;
  return _progress(participant) / target;
}

int _compare(Challenge challenge, Map<String, dynamic> a, Map<String, dynamic> b) {
  switch (challenge.winCondition) {
    case WinCondition.firstToTarget:
      final fa = progressFraction(challenge, a) ?? 0;
      final fb = progressFraction(challenge, b) ?? 0;
      return fb.compareTo(fa);
    case WinCondition.mostProgress:
      final byProgress = _progress(b).compareTo(_progress(a));
      if (byProgress != 0) return byProgress;
      return _updatedAtMillis(a).compareTo(_updatedAtMillis(b));
    case WinCondition.lastStanding:
      final outA = a['eliminatedOnDay'] as String?;
      final outB = b['eliminatedOnDay'] as String?;
      if (outA == null && outB != null) return -1;
      if (outA != null && outB == null) return 1;
      if (outA != null && outB != null && outA != outB) {
        return outB.compareTo(outA);
      }
      return _progress(b).compareTo(_progress(a));
  }
}

num _progress(Map<String, dynamic> participant) =>
    participant['progress'] as num? ?? 0;

int _updatedAtMillis(Map<String, dynamic> participant) =>
    (participant['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
    // No timestamp yet (a pending local write) sorts as most recent.
    DateTime.now().millisecondsSinceEpoch;
