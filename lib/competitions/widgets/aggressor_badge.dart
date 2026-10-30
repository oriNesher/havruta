import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../aggressor.dart';
import '../challenge.dart';

/// The Aggressor Badge's icon and colour — shared with the event carousel
/// and celebration visuals so the badge reads the same everywhere.
const IconData kAggressorIcon = Icons.sports_mma;
const Color kAggressorColor = Color(0xFFFF7A3D);

/// The badge on its holder's row: a labelled chip, or just the icon when
/// [compact]. Tapping it explains what it is. Reads "Final Aggressor" once
/// the challenge is over.
class AggressorBadge extends StatelessWidget {
  final Challenge challenge;
  final bool compact;

  const AggressorBadge({
    super.key,
    required this.challenge,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = challenge.isCompleted ? 'Final Aggressor' : 'Aggressor';

    return Tooltip(
      message: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showAggressorInfo(context, challenge),
        child: compact
            ? const Icon(kAggressorIcon, size: 16, color: kAggressorColor)
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: kAggressorColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: kAggressorColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(kAggressorIcon, size: 13, color: kAggressorColor),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: AppTheme.display(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kAggressorColor,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

void _showAggressorInfo(BuildContext context, Challenge challenge) {
  final holder = challenge.aggressorUsername ?? 'Someone';

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(kAggressorIcon, color: kAggressorColor),
                  const SizedBox(width: 10),
                  Text(
                    'Aggressor Badge',
                    style: AppTheme.display(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Goes to whoever has made the most progress per day over the '
                'last $kAggressorWindowDays days — the one raising the bar. '
                'It changes hands the moment someone pushes harder.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                challenge.isCompleted
                    ? '$holder finished as the Final Aggressor.'
                    : '$holder holds it right now.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
