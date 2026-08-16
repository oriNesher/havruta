import 'package:flutter/material.dart';

/// 3-segment progress bar shown at the bottom of the challenge-creation flow.
/// currentStep is 1-indexed: 1 = details screen, 2 = invite screen.
class ChallengeCreationStepper extends StatelessWidget {
  final int currentStep;
  static const int totalSteps = 3;

  const ChallengeCreationStepper({super.key, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        child: Row(
          children: List.generate(totalSteps, (index) {
            final filled = index < currentStep;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index == totalSteps - 1 ? 0 : 6,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 4,
                  decoration: BoxDecoration(
                    color: filled
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
