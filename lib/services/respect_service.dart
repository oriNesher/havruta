import 'package:cloud_functions/cloud_functions.dart';

/// Thin wrapper around the Respect-related Cloud Functions callables. Both
/// the daily grant and the spend touch a balance that's now socially visible
/// (the received-Respect badge on events), so — unlike purely cosmetic
/// client-trusted fields like streakCount — they're server-authoritative.
/// See functions/src/respect/.
class RespectService {
  final _functions = FirebaseFunctions.instance;

  /// Grants +1 Respect if this is the first call today (server's UTC day).
  /// Safe to call on every app open — a no-op if already granted today.
  Future<int> grantDailyRespect() async {
    final callable = _functions.httpsCallable('grantDailyRespect');
    final result = await callable.call<Map<String, dynamic>>();
    return (result.data['balance'] as num).toInt();
  }

  /// Spends 1 Respect on one event (a user can give at most one per event).
  /// Throws if the caller is the event's own actor, already gave to this
  /// event, or doesn't have enough balance.
  Future<int> giveRespect({
    required String competitionId,
    required String eventId,
  }) async {
    final callable = _functions.httpsCallable('giveRespect');
    final result = await callable.call<Map<String, dynamic>>({
      'competitionId': competitionId,
      'eventId': eventId,
    });
    return (result.data['balance'] as num).toInt();
  }
}
