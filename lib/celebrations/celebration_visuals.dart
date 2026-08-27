import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../competitions/competition_event.dart';

// Icon per celebration type — mirrors the mapping used by the inline event
// carousel (home_competitions_section.dart's _CompetitionEventRow) so the
// same event always reads the same way wherever it shows up.
IconData celebrationIcon(String type) {
  switch (type) {
    case 'overtook':
      return Icons.local_fire_department;
    case 'tookTheLead':
      return Icons.leaderboard;
    case 'pullingAhead':
      return Icons.rocket_launch;
    case 'progress':
      return Icons.trending_up;
    case 'firstBlood':
      return Icons.bloodtype;
    case 'backInRace':
      return Icons.replay;
    case 'nearCompletion':
      return Icons.flag;
    case 'milestone':
      return Icons.military_tech;
    case 'won':
      return Icons.emoji_events;
    case 'finishedInPosition':
      return Icons.check_circle;
    case 'activityStreak':
      return Icons.whatshot;
    default:
      return Icons.celebration;
  }
}

String ordinalSuffix(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

// Celebration copy is always addressed to the actor themselves (only the
// actor is ever shown their own celebration screen), so this always reads
// as "you", unlike the carousel's copy which is shown to every participant.
String celebrationHeadline(CompetitionEvent event) {
  final metadata = event.metadata ?? const {};

  switch (event.type) {
    case 'firstBlood':
      return 'First blood! You made the opening move.';
    case 'overtook':
      final target = event.targetUsername ?? 'them';
      return 'You overtook $target!';
    case 'tookTheLead':
      return 'You took the lead!';
    case 'pullingAhead':
      return "You're pulling ahead!";
    case 'milestone':
      final pct = (metadata['milestone'] as num?)?.toInt();
      return pct != null ? 'You hit $pct%!' : 'You hit a milestone!';
    case 'nearCompletion':
      return "Almost there — you're in the final stretch!";
    case 'activityStreak':
      final streak = (metadata['streak'] as num?)?.toInt();
      return streak != null
          ? '$streak-day streak! Keep it going.'
          : "You're on a streak!";
    case 'backInRace':
      return "Welcome back — you're back in the race!";
    case 'won':
      return 'You won${event.competitionTitle != null ? ' ${event.competitionTitle}' : ''}!';
    case 'finishedInPosition':
      final position = (metadata['position'] as num?)?.toInt();
      return position != null
          ? 'You finished ${ordinalSuffix(position)}!'
          : 'You finished the competition!';
    case 'progress':
      final delta = (metadata['progressDelta'] as num?)?.toInt();
      return delta != null ? 'Progress logged: +$delta!' : 'Progress logged!';
    default:
      return 'Nice work!';
  }
}

/// One event's icon + headline, shown inside the shareable card — reused by
/// both the celebration screen and the trash talk screen (which shows the
/// same events underneath the editable brag), so what caused the
/// celebration is always visible in whatever gets shared.
class CelebrationEventRow extends StatelessWidget {
  final CompetitionEvent event;

  const CelebrationEventRow({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(celebrationIcon(event.type), color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              celebrationHeadline(event),
              style: AppTheme.display(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
