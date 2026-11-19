import 'package:cloud_firestore/cloud_firestore.dart';

import '../competitions/challenge.dart';

/// One participant as the organizer dashboard (and its CSV export) shows
/// them. Pure — built from the participant doc, the challenge and the
/// organizer-only "paid" flag — so the table and the export never disagree.
class ParticipantReport {
  final int rank;
  final String uid;
  final String username;
  final String status;
  final int progress;
  final int? target;
  final int today;
  final DateTime? lastUpdate;
  final DateTime? joinedAt;
  final String? eliminatedOnDay;
  final bool paid;
  final String? teamId;

  /// Raw doc, for actions (correct/reinstate) that need more than the row.
  final Map<String, dynamic> raw;

  const ParticipantReport({
    required this.rank,
    required this.uid,
    required this.username,
    required this.status,
    required this.progress,
    required this.target,
    required this.today,
    required this.lastUpdate,
    required this.joinedAt,
    required this.eliminatedOnDay,
    required this.paid,
    required this.raw,
    this.teamId,
  });

  bool get isEliminated => eliminatedOnDay != null;

  /// Builds the rows for [ranked] participants (already in leaderboard
  /// order) on the challenge day containing [now].
  static List<ParticipantReport> build({
    required Challenge challenge,
    required List<Map<String, dynamic>> ranked,
    required Map<String, bool> paidByUid,
    required DateTime now,
  }) {
    final todayKey = challenge.dayKey(now);
    return [
      for (final (index, p) in ranked.indexed)
        _row(challenge, p, index + 1, todayKey, paidByUid),
    ];
  }

  static ParticipantReport _row(
    Challenge challenge,
    Map<String, dynamic> p,
    int rank,
    String todayKey,
    Map<String, bool> paidByUid,
  ) {
    final uid = p['uid'] as String? ?? '';
    final progress = (p['progress'] as num?)?.toInt() ?? 0;
    final daily = p['dailyProgress'] as Map<String, dynamic>? ?? const {};
    final today = (daily[todayKey] as num?)?.toInt() ?? 0;
    final eliminatedOnDay = p['eliminatedOnDay'] as String?;
    final target = challenge.targetFor(p);

    return ParticipantReport(
      rank: rank,
      uid: uid,
      username: p['username'] as String? ?? uid,
      status: statusOf(
        challenge,
        uid: uid,
        progress: progress,
        target: target,
        today: today,
        eliminatedOnDay: eliminatedOnDay,
      ),
      progress: progress,
      target: target,
      today: today,
      lastUpdate: (p['updatedAt'] as Timestamp?)?.toDate(),
      joinedAt: (p['joinedAt'] as Timestamp?)?.toDate(),
      eliminatedOnDay: eliminatedOnDay,
      paid: paidByUid[uid] ?? false,
      raw: p,
      teamId: p['teamId'] as String?,
    );
  }

  /// A participant's standing in words, per mode.
  static String statusOf(
    Challenge challenge, {
    required String uid,
    required int progress,
    required int? target,
    required int today,
    required String? eliminatedOnDay,
  }) {
    if (challenge.winnerUids.contains(uid)) return 'Winner';
    switch (challenge.winCondition) {
      case WinCondition.lastStanding:
        if (eliminatedOnDay != null) return 'Out ($eliminatedOnDay)';
        final minimum = challenge.rules.dailyMinimum;
        final startsAt = challenge.startsAt;
        if (startsAt != null && DateTime.now().isBefore(startsAt)) {
          return 'Not started';
        }
        if (challenge.isCompleted) return 'Survived';
        return minimum != null && today >= minimum ? 'Safe today' : 'In';
      case WinCondition.firstToTarget:
        return target != null && progress >= target ? 'Finished' : 'Racing';
      case WinCondition.mostProgress:
        return 'Active';
    }
  }
}

/// The participant table as CSV: UTF-8 with a byte-order mark (so Excel
/// reads Hebrew and other non-Latin names correctly), CRLF line ends,
/// RFC 4180 quoting. Personal data stays minimal — usernames only, no
/// emails (the app doesn't expose them to organizers).
String participantsCsv(
  Challenge challenge,
  List<ParticipantReport> rows, {
  Map<String, String> teamNames = const {},
}) {
  final unit = challenge.unit;
  final withTeams = teamNames.isNotEmpty;
  final header = [
    'Rank',
    'Username',
    if (withTeams) 'Team',
    'Status',
    unit.isEmpty ? 'Progress' : 'Progress ($unit)',
    if (challenge.hasTarget) 'Target',
    'Today',
    'Last update',
    'Joined',
    if (challenge.winCondition == WinCondition.lastStanding) 'Eliminated on',
    'Paid',
  ];
  final lines = [
    header,
    for (final r in rows)
      [
        '${r.rank}',
        r.username,
        if (withTeams) teamNames[r.teamId] ?? '',
        r.status,
        '${r.progress}',
        if (challenge.hasTarget) r.target?.toString() ?? '',
        '${r.today}',
        _iso(r.lastUpdate),
        _iso(r.joinedAt),
        if (challenge.winCondition == WinCondition.lastStanding)
          r.eliminatedOnDay ?? '',
        r.paid ? 'Yes' : 'No',
      ],
  ];
  return '﻿${lines.map((cells) => cells.map(_csvCell).join(',')).join('\r\n')}\r\n';
}

String _iso(DateTime? time) =>
    time == null ? '' : time.toUtc().toIso8601String().substring(0, 16);

String _csvCell(String value) {
  // Also neutralize spreadsheet formula injection: a username like
  // "=HYPERLINK(...)" must stay text when the organizer opens the file.
  final safe = value.startsWith(RegExp(r'[=+\-@\t\r]')) ? "'$value" : value;
  if (safe.contains(RegExp(r'[",\r\n]'))) {
    return '"${safe.replaceAll('"', '""')}"';
  }
  return safe;
}
