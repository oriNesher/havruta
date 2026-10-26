import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import '../services/hold_statement_store.dart';
import '../services/last_progress_amount_store.dart';
import 'challenge.dart';
import 'widgets/add_progress.dart';

/// Who may report or take back progress, and the Add Progress flow itself —
/// shared by the home card and Challenge Details so both follow one set of
/// rules.

/// Whether [me] (the viewer's participant doc) can log progress right now:
/// the challenge is running (started, not past its end), and for their mode
/// they're still in it — a race finisher is done, an eliminated player is
/// out.
bool canLogProgress(Challenge challenge, Map<String, dynamic> me) {
  if (!challenge.isActive) return false;
  final now = DateTime.now();
  final endsAt = challenge.endsAt;
  if (endsAt != null && !now.isBefore(endsAt)) return false;

  switch (challenge.winCondition) {
    case WinCondition.firstToTarget:
      final target = challenge.targetFor(me);
      final progress = (me['progress'] as num? ?? 0).toInt();
      return target != null && progress < target;
    case WinCondition.mostProgress:
      return true;
    case WinCondition.lastStanding:
      final startsAt = challenge.startsAt;
      if (startsAt != null && now.isBefore(startsAt)) return false;
      return me['eliminatedOnDay'] == null;
  }
}

/// Whether [me] can take some of their progress back: the challenge is
/// still running, they're not out, and there's progress to reduce.
bool canEditProgress(Challenge challenge, Map<String, dynamic> me) {
  final progress = (me['progress'] as num? ?? 0).toInt();
  return challenge.isActive && me['eliminatedOnDay'] == null && progress > 0;
}

/// How much more [me] can log before overshooting their goal — only a race
/// has a finish line to cap at; the other modes have no ceiling.
int? remainingToGoal(Challenge challenge, Map<String, dynamic> me) {
  if (challenge.winCondition != WinCondition.firstToTarget) return null;
  final target = challenge.targetFor(me);
  if (target == null) return null;
  final progress = (me['progress'] as num? ?? 0).toInt();
  return (target - progress).clamp(0, target);
}

/// Runs the Add Progress flow for [uid] in [challenge]: the hold-to-submit
/// popup prefilled with their last amount and capped at what's left of a
/// race, then the write. [onSubmitting] brackets the write itself, so the
/// caller can disable its button while it's in flight.
Future<void> reportProgress(
  BuildContext context, {
  required Challenge challenge,
  required Map<String, dynamic> me,
  required String uid,
  required ValueChanged<bool> onSubmitting,
}) async {
  final lastAmountStore = LastProgressAmountStore();
  final holdStatementStore = HoldStatementStore();

  final lastAmount = await lastAmountStore.getLastAmount(uid, challenge.id);
  final holdStatement = await holdStatementStore.currentStatement();
  if (!context.mounted) return;

  final maxAmount = remainingToGoal(challenge, me);
  final unit = me['unit'] as String? ?? challenge.unit;
  var initialAmount = lastAmount ?? 1;
  if (maxAmount != null && initialAmount > maxAmount) {
    initialAmount = maxAmount;
  }

  final amount = await showAddProgressDialog(
    context,
    competitionId: challenge.id,
    initialAmount: initialAmount,
    holdStatement: holdStatement,
    maxAmount: maxAmount,
    unit: unit,
  );
  if (amount == null || !context.mounted) return;

  if (amount > 0) {
    onSubmitting(true);
    try {
      await FirestoreService().addProgress(
        competitionId: challenge.id,
        uid: uid,
        amount: amount,
        dayKey: challenge.dayKey(DateTime.now()),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating progress: $e')),
        );
      }
    } finally {
      if (context.mounted) onSubmitting(false);
    }
  }
  await lastAmountStore.saveLastAmount(uid, challenge.id, amount);
  await holdStatementStore.advance();
}
