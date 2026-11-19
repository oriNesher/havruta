import 'challenge.dart';

/// One team's line on the team leaderboard.
class TeamStanding {
  final String teamId;
  final String name;
  final int members;

  /// Average progress per member — so a team of 6 can fairly beat a team
  /// of 12 (decided with the product owner, 2026-11-20).
  final double average;

  /// Members not eliminated (what Last One Standing ranks teams on first).
  final int stillIn;

  const TeamStanding({
    required this.teamId,
    required this.name,
    required this.members,
    required this.average,
    required this.stillIn,
  });
}

/// Ranks [teams] (id → name) from their members among [participants]
/// (participants/{uid}.teamId), best first. Teams don't decide individual
/// winners; this is a leaderboard of its own. Last One Standing ranks by
/// members still in, then average; every other mode by average. Teams
/// with nobody on them sort last.
List<TeamStanding> teamStandings(
  Challenge challenge,
  Map<String, String> teams,
  Iterable<Map<String, dynamic>> participants,
) {
  final standings = [
    for (final MapEntry(key: teamId, value: name) in teams.entries)
      () {
        final members = participants
            .where((p) => p['teamId'] == teamId)
            .toList();
        final total = members.fold<int>(
          0,
          (sum, p) => sum + ((p['progress'] as num?)?.toInt() ?? 0),
        );
        return TeamStanding(
          teamId: teamId,
          name: name,
          members: members.length,
          average: members.isEmpty ? 0 : total / members.length,
          stillIn: members.where((p) => p['eliminatedOnDay'] == null).length,
        );
      }(),
  ];

  final los = challenge.winCondition == WinCondition.lastStanding;
  standings.sort((a, b) {
    if ((a.members == 0) != (b.members == 0)) return a.members == 0 ? 1 : -1;
    if (los && a.stillIn != b.stillIn) return b.stillIn.compareTo(a.stillIn);
    final byAverage = b.average.compareTo(a.average);
    return byAverage != 0 ? byAverage : a.name.compareTo(b.name);
  });
  return standings;
}
