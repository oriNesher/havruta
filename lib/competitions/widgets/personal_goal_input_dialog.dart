import 'package:flutter/material.dart';

/// Shared dialog for capturing a participant's own goal/target/unit when
/// joining a personalGoalChallenge — used both for accepting a direct
/// (username/email) invite and for redeeming a shared invite link, since
/// both paths hit the same "personal goal challenges need your own goal
/// before you can join" rule.
///
/// [onSubmit] performs the actual join (accept invite / redeem link) and
/// should rethrow on failure — the dialog shows the error and stays open.
/// Returns true if the join succeeded, false if the user cancelled.
Future<bool> showPersonalGoalInputDialog({
  required BuildContext context,
  required String competitionTitle,
  String? creatorGoalTitle,
  int? creatorTargetValue,
  String? creatorUnit,
  required Future<void> Function(
    String goalTitle,
    int targetValue,
    String unit,
  )
  onSubmit,
  String submitLabel = 'Join',
}) async {
  final goalTitleController = TextEditingController();
  final targetValueController = TextEditingController();
  final unitController = TextEditingController();
  bool isSubmitting = false;
  bool joined = false;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogInnerContext, setDialogState) {
          Future<void> submit() async {
            final goalTitle = goalTitleController.text.trim();
            final targetValueText = targetValueController.text.trim();
            final unit = unitController.text.trim();

            if (goalTitle.isEmpty || targetValueText.isEmpty || unit.isEmpty) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('Please fill all fields')),
              );
              return;
            }

            final targetValue = int.tryParse(targetValueText);
            if (targetValue == null || targetValue <= 0) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('Target value must be a positive number'),
                ),
              );
              return;
            }

            setDialogState(() => isSubmitting = true);

            try {
              await onSubmit(goalTitle, targetValue, unit);
              joined = true;

              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
            } catch (e) {
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(
                dialogContext,
              ).showSnackBar(SnackBar(content: Text('Error: $e')));
            } finally {
              if (!joined && dialogContext.mounted) {
                setDialogState(() => isSubmitting = false);
              }
            }
          }

          final hasCreatorGoal =
              creatorGoalTitle != null &&
              creatorGoalTitle.isNotEmpty &&
              creatorTargetValue != null;
          final creatorGoalDisplay = hasCreatorGoal
              ? (creatorUnit != null && creatorUnit.isNotEmpty
                    ? '$creatorGoalTitle — $creatorTargetValue $creatorUnit'
                    : '$creatorGoalTitle — $creatorTargetValue')
              : null;

          return AlertDialog(
            title: Text('Join "$competitionTitle"'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (creatorGoalDisplay != null) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Creator's goal, for reference:",
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          dialogContext,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        creatorGoalDisplay,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Define your personal goal for this challenge'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: goalTitleController,
                    enabled: !isSubmitting,
                    decoration: const InputDecoration(
                      labelText: 'My goal',
                      hintText: 'Get fitter / Study more / Read more',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: targetValueController,
                    enabled: !isSubmitting,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'My target value',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: unitController,
                    enabled: !isSubmitting,
                    decoration: const InputDecoration(
                      labelText: 'My unit',
                      hintText: 'pushups / minutes / pages / km',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSubmitting ? null : submit,
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(submitLabel),
              ),
            ],
          );
        },
      );
    },
  );

  goalTitleController.dispose();
  targetValueController.dispose();
  unitController.dispose();

  return joined;
}
