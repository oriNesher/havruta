import 'package:flutter/material.dart';

import '../app_theme.dart';

/// The message that closes the initial guided narrative, shown once on Home
/// after its last module completes. It closes only through [onDone], so
/// "has the user seen it?" is never left ambiguous.
Future<void> showOnboardingCompletionDialog({
  required BuildContext context,
  required VoidCallback onDone,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF2A2A42)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "You're ready.",
                style: AppTheme.display(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Join Challenges, make progress, react to your friends, and '
                'create your own. Your next mission is simple — win the '
                "Challenge that's still waiting for you, and win the one you "
                'just created.',
                style: Theme.of(dialogContext).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  onDone();
                  Navigator.of(dialogContext).pop();
                },
                child: const Text("Let's go"),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
