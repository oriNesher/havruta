import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the amount a user last reported for a competition, so the
/// add-progress popup can prefill with it next time instead of starting
/// blank.
class LastProgressAmountStore {
  Future<void> saveLastAmount(
    String uid,
    String competitionId,
    int amount,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(uid, competitionId), amount);
  }

  Future<int?> getLastAmount(String uid, String competitionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key(uid, competitionId));
  }

  String _key(String uid, String competitionId) =>
      'last_progress_amount_${uid}_$competitionId';
}
