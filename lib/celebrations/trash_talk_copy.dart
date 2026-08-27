import '../competitions/competition_event.dart';
import 'celebration_types.dart';
import 'celebration_visuals.dart';

// Boastful, shareable line for the single highest-priority event in a
// batch — this is the headline of the suggested trash talk message.
String _headlineLine(CompetitionEvent event) {
  final metadata = event.metadata ?? const {};

  switch (event.type) {
    case 'firstBlood':
      return "First blood is mine. Who's next?";
    case 'overtook':
      final target = event.targetUsername ?? 'you';
      return 'Just blew past $target. Catch me if you can.';
    case 'tookTheLead':
      return "Guess who's #1 now.";
    case 'pullingAhead':
      return 'Widening the gap as we speak.';
    case 'milestone':
      final pct = (metadata['milestone'] as num?)?.toInt();
      return pct != null
          ? '$pct% down. Basically done at this point.'
          : 'Hit a milestone. Basically done at this point.';
    case 'nearCompletion':
      return "So close to done I can taste it.";
    case 'activityStreak':
      final streak = (metadata['streak'] as num?)?.toInt();
      return streak != null
          ? '$streak days straight. Consistency is my whole personality.'
          : "On a streak. Consistency is my whole personality.";
    case 'backInRace':
      return "Told you I wasn't out. I'm back.";
    case 'won':
      return "Champion. That's it, that's the whole message.";
    case 'finishedInPosition':
      final position = (metadata['position'] as num?)?.toInt();
      return position != null
          ? 'Finished ${ordinalSuffix(position)}. Not bad at all.'
          : 'Finished strong. Not bad at all.';
    case 'progress':
      return 'Put in the work today.';
    default:
      return 'Just made some noise.';
  }
}

// Short parenthetical fragment for every other event riding along in the
// same batch, so a milestone hit alongside taking the lead doesn't get
// buried — it just isn't the headline.
String _secondaryFragment(CompetitionEvent event) {
  final metadata = event.metadata ?? const {};

  switch (event.type) {
    case 'firstBlood':
      return 'first blood';
    case 'overtook':
      return 'overtook ${event.targetUsername ?? 'someone'}';
    case 'tookTheLead':
      return 'took the lead';
    case 'pullingAhead':
      return 'pulling ahead';
    case 'milestone':
      final pct = (metadata['milestone'] as num?)?.toInt();
      return pct != null ? 'hit $pct%' : 'hit a milestone';
    case 'nearCompletion':
      return 'almost done';
    case 'activityStreak':
      final streak = (metadata['streak'] as num?)?.toInt();
      return streak != null ? '$streak-day streak' : 'on a streak';
    case 'backInRace':
      return 'back in it';
    case 'won':
      return 'won it all';
    case 'finishedInPosition':
      final position = (metadata['position'] as num?)?.toInt();
      return position != null ? 'finished ${ordinalSuffix(position)}' : 'finished';
    case 'progress':
      return 'logged progress';
    default:
      return '';
  }
}

/// Builds one combined suggested message for every celebration-eligible
/// event in a batch: the highest-priority event drives the headline brag,
/// the rest ride along as a short parenthetical rather than each getting
/// their own line — reads better as one brag than a bullet list.
String buildSuggestedTrashTalk(List<CompetitionEvent> events) {
  if (events.isEmpty) return '';

  final sorted = [...events]..sort(
    (a, b) => celebrationPriorityRank(a.type).compareTo(celebrationPriorityRank(b.type)),
  );

  final headline = _headlineLine(sorted.first);
  final extras = sorted
      .skip(1)
      .map(_secondaryFragment)
      .where((fragment) => fragment.isNotEmpty)
      .toList();

  if (extras.isEmpty) return headline;
  return '$headline (+ ${extras.join(', ')})';
}
