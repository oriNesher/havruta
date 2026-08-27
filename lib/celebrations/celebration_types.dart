// Event types the actor gets a full-screen celebration for. Kept in sync by
// hand with the backend's copy at
// functions/src/events/celebrationTypes.ts — there's no shared codegen
// between the two packages.
const List<String> kCelebrationTypes = [
  'firstBlood',
  'overtook',
  'tookTheLead',
  'pullingAhead',
  'milestone',
  'nearCompletion',
  'activityStreak',
  'backInRace',
  'won',
  'finishedInPosition',
  'progress',
];

// Highest-impact first. Drives which event in a batch becomes the Trash
// Talk headline and the order celebration rows are listed in. Types not
// listed here (there shouldn't be any, given kCelebrationTypes above) sort
// last.
const List<String> kCelebrationPriority = [
  'won',
  'firstBlood',
  'finishedInPosition',
  'milestone',
  'tookTheLead',
  'pullingAhead',
  'nearCompletion',
  'backInRace',
  'activityStreak',
  'overtook',
  'progress',
];

int celebrationPriorityRank(String type) {
  final index = kCelebrationPriority.indexOf(type);
  return index == -1 ? kCelebrationPriority.length : index;
}
