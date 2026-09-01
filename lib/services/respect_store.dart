import 'package:flutter/foundation.dart';

/// Client-side Respect balance tracking, mirroring the singleton-cache shape
/// of ProgressSnapshotCache (lib/services/progress_snapshot_cache.dart).
///
/// A give is capped at 1 per event (enforced server-side), so there's no
/// batching to do here — this just keeps the balance shown across the app
/// (Home screen text, every event's Give Respect button) in sync: the last
/// confirmed server value, minus however many gives are currently in flight,
/// so the number drops the instant someone taps rather than waiting on a
/// round trip.
class RespectStore extends ChangeNotifier {
  RespectStore._();
  static final RespectStore instance = RespectStore._();

  int _serverBalance = 0;
  int _pendingSpend = 0;

  int get displayBalance => (_serverBalance - _pendingSpend).clamp(0, 1 << 31);

  /// Called from a live listener on the user doc whenever the server
  /// balance changes (daily grant or a confirmed spend).
  void updateServerBalance(int balance) {
    _serverBalance = balance;
    notifyListeners();
  }

  /// Call right before issuing a giveRespect request, so the displayed
  /// balance drops immediately.
  void beginSpend() {
    _pendingSpend += 1;
    notifyListeners();
  }

  /// Call once the request settles. On success, reconciles with the
  /// server's returned balance; on failure, just releases the optimistic hold.
  void endSpend({required bool success, int? newBalance}) {
    _pendingSpend = (_pendingSpend - 1).clamp(0, 1 << 31);
    if (success && newBalance != null) {
      _serverBalance = newBalance;
    }
    notifyListeners();
  }

  /// Clears all state on sign-out so a new session doesn't inherit the
  /// previous user's balance.
  void reset() {
    _serverBalance = 0;
    _pendingSpend = 0;
  }
}
