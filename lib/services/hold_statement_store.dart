import 'package:shared_preferences/shared_preferences.dart';

import '../home/add_progress_copy.dart';

/// Rotation cursor for the "Take a moment to…" lines shown during the
/// add-progress hold (see kHoldStatements).
///
/// Persisted rather than in-memory so the rotation survives app restarts —
/// an in-memory cursor would snap back to the first line every cold start,
/// which is exactly the repetition the rotation exists to hide. The cursor
/// is a single global count, not per-challenge: it's about how often *this
/// person* has seen the copy, not about any one challenge.
class HoldStatementStore {
  static const _key = 'add_progress_hold_statement_index';

  /// The line to show for the next submission.
  Future<String> currentStatement() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_key) ?? 0;
    return kHoldStatements[index % kHoldStatements.length];
  }

  /// Moves the cursor on, so the next hold shows a different line. Called
  /// after a completed submission, not when the dialog merely opens — a
  /// cancelled dialog shouldn't burn a line the user never finished reading.
  Future<void> advance() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_key) ?? 0;
    await prefs.setInt(_key, (index + 1) % kHoldStatements.length);
  }
}
