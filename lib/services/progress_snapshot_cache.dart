import 'firestore_service.dart';

class ProgressSnapshotCache {
  ProgressSnapshotCache._();
  static final ProgressSnapshotCache instance = ProgressSnapshotCache._();

  String? _uid;
  // What the user saw at the start of the current session (read from Firestore once)
  final Map<String, Map<String, int>> _previous = {};
  // What the user is currently seeing (updated on every stream emit, written on app pause)
  final Map<String, Map<String, int>> _current = {};
  final Set<String> _loaded = {};
  final Map<String, Future<void>> _pending = {};

  void _initForUser(String uid) {
    if (_uid == uid) return;
    _uid = uid;
    _previous.clear();
    _current.clear();
    _loaded.clear();
    _pending.clear();
  }

  /// Load the previous-session snapshot for one competition.
  /// Safe to call multiple times — subsequent calls within the same session are instant no-ops.
  Future<void> ensureLoaded(
    String uid,
    String competitionId,
    FirestoreService service,
  ) async {
    _initForUser(uid);
    if (_loaded.contains(competitionId)) return;
    if (_pending.containsKey(competitionId)) {
      await _pending[competitionId];
      return;
    }
    final future = _fetch(uid, competitionId, service);
    _pending[competitionId] = future;
    await future;
  }

  Future<void> _fetch(
    String uid,
    String competitionId,
    FirestoreService service,
  ) async {
    final snapshot = await service.getCompetitionSnapshot(uid, competitionId);
    if (snapshot != null && snapshot.isNotEmpty) {
      _previous[competitionId] = snapshot;
    }
    _loaded.add(competitionId);
    _pending.remove(competitionId);
  }

  /// The session-start snapshot for a competition (null = first ever visit).
  Map<String, int>? getPrevious(String competitionId) => _previous[competitionId];

  /// Record what the user is currently seeing. Called on every stream emit.
  void updateCurrent(String competitionId, Map<String, int> progress) {
    _current[competitionId] = Map.from(progress);
  }

  /// Write current progress to Firestore. Called on app pause.
  Future<void> persist(FirestoreService service) async {
    final uid = _uid;
    if (uid == null || _current.isEmpty) return;
    for (final entry in _current.entries) {
      await service.saveCompetitionSnapshot(uid, entry.key, entry.value);
    }
  }

  /// Persist then wipe the cache. Called on sign-out.
  Future<void> persistAndClear(FirestoreService service) async {
    await persist(service);
    _uid = null;
    _previous.clear();
    _current.clear();
    _loaded.clear();
    _pending.clear();
  }
}