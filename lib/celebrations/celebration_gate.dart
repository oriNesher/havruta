import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../competitions/competition_event.dart';
import '../services/firestore_service.dart';
import 'celebration_screen.dart';
import 'celebration_types.dart';

/// Mounted once, high in the authenticated app shell (see AuthGate), so a
/// celebration can be pushed on top of whatever screen the user happens to
/// be on when the triggering Cloud Function finishes — not just the home
/// screen, since progress can also be logged from competition details.
///
/// Listens for celebration-eligible events belonging to this user that
/// haven't been celebrated yet, groups them by batchId (all events fired by
/// the same progress update), and shows one CelebrationScreen per batch —
/// queuing any further batches that arrive while one is already showing.
class CelebrationGate extends StatefulWidget {
  final String uid;
  final Widget child;

  const CelebrationGate({super.key, required this.uid, required this.child});

  @override
  State<CelebrationGate> createState() => _CelebrationGateState();
}

class _CelebrationGateState extends State<CelebrationGate> {
  final FirestoreService _firestoreService = FirestoreService();
  late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
  _subscription;

  // Latest known events for each pending batch, keyed by batchId. Kept
  // fresh on every snapshot so that if a batch's content changes before
  // it's shown — e.g. its "progress" event gets merged into a newer batch
  // and takes on that batch's id — the stale id is simply absent here by
  // the time the queue reaches it.
  final Map<String, List<CompetitionEvent>> _eventsByBatchId = {};
  final List<String> _queue = [];
  final Set<String> _queuedBatchIds = {};
  bool _isShowing = false;

  @override
  void initState() {
    super.initState();
    _subscription = _firestoreService
        .getPendingCelebrations(widget.uid)
        .listen(_onSnapshot, onError: _onSnapshotError);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  void _onSnapshotError(Object error, StackTrace stackTrace) {
    // An unhandled error on a bare stream subscription propagates to the
    // zone as an uncaught exception instead of just failing this feature
    // quietly — worth a hard stop here since CelebrationGate wraps the
    // whole authenticated app shell.
    debugPrint('Pending celebrations stream error: $error');
  }

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final events = snapshot.docs
        .map(CompetitionEvent.fromDoc)
        .where((e) => kCelebrationTypes.contains(e.type) && e.batchId != null)
        .toList();

    _eventsByBatchId
      ..clear()
      ..addAll(_groupByBatchId(events));

    for (final batchId in _eventsByBatchId.keys) {
      if (_queuedBatchIds.add(batchId)) {
        _queue.add(batchId);
      }
    }

    _maybeShowNext();
  }

  Map<String, List<CompetitionEvent>> _groupByBatchId(
    List<CompetitionEvent> events,
  ) {
    final map = <String, List<CompetitionEvent>>{};
    for (final event in events) {
      map.putIfAbsent(event.batchId!, () => []).add(event);
    }
    return map;
  }

  void _maybeShowNext() {
    if (_isShowing || _queue.isEmpty || !mounted) return;

    final batchId = _queue.removeAt(0);
    final events = _eventsByBatchId[batchId];
    if (events == null || events.isEmpty) {
      // Vanished before we got to it (merged into a different batch,
      // celebrated from another device, etc.) — move on to the next one.
      _maybeShowNext();
      return;
    }

    _isShowing = true;
    // Defer off the snapshot-delivery callstack before pushing a route.
    Future.microtask(() => _show(events));
  }

  Future<void> _show(List<CompetitionEvent> events) async {
    if (!mounted) {
      _isShowing = false;
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CelebrationScreen(events: events),
      ),
    );

    try {
      await _firestoreService.markEventsCelebrated(
        events.map((e) => e.reference).toList(),
      );
    } catch (e) {
      debugPrint('Failed to mark celebration(s) as seen: $e');
    }

    _isShowing = false;
    if (mounted) _maybeShowNext();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
