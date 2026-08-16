import 'package:shared_preferences/shared_preferences.dart';

/// Persists an invite-link token across process death — the interruption a
/// user goes through when a deep link requires them to log in, register, or
/// install the app before they can redeem it. SharedPreferences (not
/// in-memory state) is required specifically because that interruption can
/// span an app restart.
class PendingInviteStore {
  static const _key = 'pending_invite_link_id';

  Future<void> savePendingInviteToken(String linkId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, linkId);
  }

  Future<String?> getPendingInviteToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> clearPendingInviteToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
