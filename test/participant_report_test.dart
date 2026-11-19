import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:havruta/competitions/challenge.dart';
import 'package:havruta/organizer/participant_report.dart';

void main() {
  final race = Challenge.fromDoc('c1', {
    'title': 'Run club',
    'createdBy': 'alice',
    'winCondition': 'firstToTarget',
    'sharedTargetValue': 100,
    'sharedUnit': 'km',
  });
  final now = DateTime.utc(2026, 11, 19, 12);

  List<ParticipantReport> rows(
    Challenge challenge,
    List<Map<String, dynamic>> people, [
    Map<String, bool> paid = const {},
  ]) => ParticipantReport.build(
    challenge: challenge,
    ranked: people,
    paidByUid: paid,
    now: now,
  );

  test('a row carries rank, status, today and the paid flag', () {
    final [bob, carol] = rows(race, [
      {
        'uid': 'bob', 'username': 'Bob', 'progress': 100,
        'dailyProgress': {'2026-11-19': 7},
        'updatedAt': Timestamp.fromDate(now),
      },
      {'uid': 'carol', 'username': 'Carol', 'progress': 20},
    ], {'bob': true});
    expect(bob.rank, 1);
    expect(bob.status, 'Finished');
    expect(bob.today, 7);
    expect(bob.paid, isTrue);
    expect(carol.rank, 2);
    expect(carol.status, 'Racing');
    expect(carol.paid, isFalse);
  });

  test('Last One Standing statuses', () {
    final los = Challenge.fromDoc('c2', {
      'createdBy': 'alice',
      'winCondition': 'lastStanding',
      'rules': {'dailyMinimum': 5},
      'startsAt': Timestamp.fromDate(DateTime.utc(2026, 11, 1)),
    });
    final [safe, inRow, out] = rows(los, [
      {'uid': 'a', 'progress': 9, 'dailyProgress': {'2026-11-19': 5}},
      {'uid': 'b', 'progress': 9, 'dailyProgress': {'2026-11-19': 2}},
      {'uid': 'c', 'progress': 1, 'eliminatedOnDay': '2026-11-03'},
    ]);
    expect(safe.status, 'Safe today');
    expect(inRow.status, 'In');
    expect(out.status, 'Out (2026-11-03)');
    expect(out.isEliminated, isTrue);
  });

  test('the CSV opens cleanly in Excel, Hebrew names included', () {
    final csv = participantsCsv(race, rows(race, [
      {'uid': 'd', 'username': 'דנה', 'progress': 40},
    ]));
    expect(csv.startsWith('﻿'), isTrue);
    final lines = csv.substring(1).split('\r\n');
    expect(lines[0],
        'Rank,Username,Status,Progress (km),Target,Today,Last update,Joined,Paid');
    expect(lines[1], '1,דנה,Racing,40,100,0,,,No');
    expect(lines.last, '');
  });

  test('commas and quotes are quoted; formulas stay text', () {
    final csv = participantsCsv(race, rows(race, [
      {'uid': 'x', 'username': 'Smith, "Jo"', 'progress': 1},
      {'uid': 'y', 'username': '=HYPERLINK("http://evil")', 'progress': 0},
    ]));
    expect(csv, contains('"Smith, ""Jo"""'));
    expect(csv, contains('"\'=HYPERLINK(""http://evil"")"'));
  });
}
