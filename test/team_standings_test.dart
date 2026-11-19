import 'package:flutter_test/flutter_test.dart';
import 'package:havruta/competitions/challenge.dart';
import 'package:havruta/competitions/team_standings.dart';
import 'package:havruta/organizer/participant_report.dart';

void main() {
  Challenge challenge(Map<String, dynamic> data) =>
      Challenge.fromDoc('c1', {'createdBy': 'alice', ...data});

  group('large vs friend challenges (mirrors isLargeChallenge)', () {
    List<String> uids(int n) => [for (var i = 0; i < n; i++) 'u$i'];

    test('above 15 participants it scales, unless overridden', () {
      expect(Challenge.largeThreshold, 15);
      expect(challenge({'participantUids': uids(15)}).isLarge, isFalse);
      expect(challenge({'participantUids': uids(16)}).isLarge, isTrue);
      expect(
        challenge({
          'participantUids': uids(16),
          'social': {'scale': 'small'},
        }).isLarge,
        isFalse,
      );
      expect(
        challenge({
          'participantUids': uids(3),
          'social': {'scale': 'large'},
        }).isLarge,
        isTrue,
      );
    });

    test('Trash Talk: on for friends, off for large or organizer-only', () {
      expect(
        challenge({'participantUids': ['alice', 'bob']}).trashTalkEnabled,
        isTrue,
      );
      expect(
        challenge({'participantUids': uids(20)}).trashTalkEnabled,
        isFalse,
      );
      // The creator only organizes.
      expect(
        challenge({'participantUids': ['bob']}).trashTalkEnabled,
        isFalse,
      );
      // An organizer's explicit choice wins either way.
      expect(
        challenge({
          'participantUids': uids(20),
          'social': {'trashTalk': true},
        }).trashTalkEnabled,
        isTrue,
      );
      expect(
        challenge({
          'participantUids': ['alice'],
          'social': {'trashTalk': false},
        }).trashTalkEnabled,
        isFalse,
      );
    });
  });

  group('team standings', () {
    final race = challenge({'winCondition': 'mostProgress'});
    const teams = {'red': 'Red', 'blue': 'Blue', 'empty': 'Empty'};

    test('ranked by average per member, so size alone does not win', () {
      final standings = teamStandings(race, teams, [
        {'uid': 'a', 'teamId': 'red', 'progress': 30},
        {'uid': 'b', 'teamId': 'red', 'progress': 10},
        {'uid': 'c', 'teamId': 'blue', 'progress': 25},
        {'uid': 'd', 'teamId': 'blue', 'progress': 25},
        {'uid': 'e', 'teamId': 'blue', 'progress': 25},
        {'uid': 'f', 'progress': 999}, // on no team
      ]);
      expect(standings.map((t) => t.name), ['Blue', 'Red', 'Empty']);
      expect(standings[0].average, 25);
      expect(standings[0].members, 3);
      expect(standings[1].average, 20);
      expect(standings[2].members, 0);
    });

    test('Last One Standing ranks by members still in first', () {
      final los = challenge({'winCondition': 'lastStanding'});
      final standings = teamStandings(los, teams, [
        {'uid': 'a', 'teamId': 'red', 'progress': 90},
        {'uid': 'b', 'teamId': 'red', 'progress': 90,
          'eliminatedOnDay': '2026-11-18'},
        {'uid': 'c', 'teamId': 'blue', 'progress': 10},
        {'uid': 'd', 'teamId': 'blue', 'progress': 10},
      ]);
      expect(standings.first.name, 'Blue');
      expect(standings.first.stillIn, 2);
    });
  });

  test('the CSV gets a Team column once there are teams', () {
    final race = challenge({'winCondition': 'mostProgress'});
    final rows = ParticipantReport.build(
      challenge: race,
      ranked: [
        {'uid': 'a', 'username': 'Ana', 'progress': 5, 'teamId': 'red'},
        {'uid': 'b', 'username': 'Ben', 'progress': 3},
      ],
      paidByUid: const {},
      now: DateTime.utc(2026, 11, 20),
    );
    final lines = participantsCsv(race, rows, teamNames: {'red': 'Red'})
        .substring(1)
        .split('\r\n');
    expect(lines[0].startsWith('Rank,Username,Team,Status'), isTrue);
    expect(lines[1].startsWith('1,Ana,Red,'), isTrue);
    expect(lines[2].startsWith('2,Ben,,'), isTrue);
  });
}
