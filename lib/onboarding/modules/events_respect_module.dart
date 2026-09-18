import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../onboarding_ids.dart';
import '../onboarding_repository.dart';
import '../onboarding_state.dart';
import 'onboarding_module.dart';

/// Module 4 — Events and Respect, taught on a real Event in Challenge B
/// ("Challenge two friends").
///
/// On start it asks the backend (ensureOnboardingSystemProgress) to have
/// the system user "Havruta" make its one real progress update there
/// (0 → 1 of 2 friends). That call is idempotent server-side, so it's made
/// on every start — a retry, relaunch or duplicate start converges on the
/// same single update. The module never writes an event: it waits for the
/// normal Events pipeline's "progress" event for that update, identified
/// by actor + type + its 0 → 1 metadata (never by title or position), and
/// guides the anchors the Home carousel exposes for that exact event id.
///
/// Steps:
///   1. Event explained — the user pressed "Next" on the Event (in memory:
///      a relaunch simply shows the explanation again).
///   2. Respect given — the event's real `respectGivenBy` contains the
///      user. Only the giveRespect callable writes that field, so this is
///      server-confirmed, never an optimistic tap. Before step 2 is shown
///      the user's balance must be ≥ 1; if it's empty, the one-time,
///      server-side ensureOnboardingRespect grant tops it up.
class EventsRespectModule extends OnboardingModule {
  static const eventMessage =
      'Every progress update creates events inside the Challenge. This is '
      "how you see what the people you're competing with are doing.";
  static const respectMessage =
      "Respect is how you acknowledge someone else's progress. You have a "
      'limited amount to give, so use it when someone earns it.';

  /// Events from one progress update land a moment apart, and the carousel
  /// jumps to whichever is newest — so wait for the batch to settle before
  /// pointing at one, instead of the spotlight chasing the carousel.
  static const _eventSettleDelay = Duration(milliseconds: 1500);

  OnboardingModuleHost? _host;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _settleTimer;
  bool _stopped = false;
  bool _completed = false;

  String? _competitionId;
  bool? _challengeVerified;
  int? _systemProgress;
  String _systemProgressCall = '(not called)';

  String? _eventId;
  String? _eventBatchId;
  List<String> _respectGivenBy = const [];
  bool _eventsLoaded = false;
  bool _eventSettled = false;

  int? _balance;
  bool _grantRequested = false;
  String _grantCall = '(not needed yet)';

  bool _eventExplained = false;

  @override
  OnboardingModuleId get id => OnboardingModuleId.eventsRespect;

  bool get _respectGiven {
    final uid = _host?.uid;
    return uid != null && _respectGivenBy.contains(uid);
  }

  /// Refuses to start unless Challenge B really exists as this user's
  /// onboarding challenge and they've joined it (Module 1's outcome).
  @override
  Future<void> prepare(OnboardingModuleHost host) async {
    final competitionId = await host.repository.onboardingCompetitionIdFor(
      host.uid,
      OnboardingChallengeKey.challengeFriends,
    );
    final competition = await FirebaseFirestore.instance
        .collection('competitions')
        .doc(competitionId)
        .get(const GetOptions(source: Source.server));
    final data = competition.data();
    if (data == null ||
        !OnboardingRepository.isOnboardingChallengeFor(
          data,
          host.uid,
          OnboardingChallengeKey.challengeFriends,
        )) {
      throw StateError('Challenge B ($competitionId) is missing or not ours');
    }
    final participant = await competition.reference
        .collection('participants')
        .doc(host.uid)
        .get(const GetOptions(source: Source.server));
    if (!participant.exists) {
      throw StateError('Not a participant of Challenge B yet (Module 1)');
    }
  }

  @override
  void start(OnboardingModuleHost host) {
    _host = host;
    _watch(host);
  }

  Future<void> _watch(OnboardingModuleHost host) async {
    final competitionId = await host.repository.onboardingCompetitionIdFor(
      host.uid,
      OnboardingChallengeKey.challengeFriends,
    );
    if (_stopped) return;
    _competitionId = competitionId;
    final repo = host.repository;

    _subscriptions.addAll([
      repo
          .watchCompetition(competitionId)
          .listen(_onCompetition, onError: _onError),
      repo
          .watchParticipant(competitionId, onboardingSystemUserUid)
          .listen(_onSystemParticipant, onError: _onError),
      repo
          .watchSystemProgressEvents(competitionId)
          .listen(_onSystemEvents, onError: _onError),
      repo.watchUser(host.uid).listen(_onUser, onError: _onError),
    ]);

    unawaited(_ensureSystemProgress(host));
  }

  void _onError(Object e) => debugPrint('Onboarding Module 4 watch error: $e');

  /// Safe to call on every start: the server applies Havruta's update at
  /// most once. Retried a few times so a flaky network on the first try
  /// doesn't leave the module waiting forever.
  Future<void> _ensureSystemProgress(OnboardingModuleHost host) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
      if (_stopped) return;
      _systemProgressCall = 'calling (attempt ${attempt + 1})';
      try {
        final applied = await host.repository.ensureSystemProgress();
        if (_stopped) return;
        _systemProgressCall = applied ? 'applied now' : 'already applied';
        _changed();
        return;
      } catch (e) {
        _systemProgressCall = 'error: $e';
        debugPrint('Onboarding Module 4 system progress error: $e');
      }
    }
  }

  void _onCompetition(DocumentSnapshot<Map<String, dynamic>> snap) {
    final host = _host;
    if (_stopped || host == null) return;
    final data = snap.data();
    _challengeVerified =
        data != null &&
        OnboardingRepository.isOnboardingChallengeFor(
          data,
          host.uid,
          OnboardingChallengeKey.challengeFriends,
        );
    _changed();
  }

  void _onSystemParticipant(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (_stopped) return;
    _systemProgress = (snap.data()?['progress'] as num?)?.toInt();
    _changed();
  }

  void _onSystemEvents(QuerySnapshot<Map<String, dynamic>> snap) {
    if (_stopped) return;
    _eventsLoaded = true;
    QueryDocumentSnapshot<Map<String, dynamic>>? match;
    for (final doc in snap.docs) {
      if (OnboardingRepository.isSystemOnboardingProgressEvent(doc.data())) {
        match = doc;
        break;
      }
    }
    final data = match?.data();
    if (match?.id != _eventId) {
      _eventSettled = false;
      _settleTimer?.cancel();
      if (match != null) {
        _settleTimer = Timer(_eventSettleDelay, () {
          if (_stopped) return;
          _eventSettled = true;
          _changed();
        });
      }
    }
    _eventId = match?.id;
    _eventBatchId = data?['batchId'] as String?;
    _respectGivenBy =
        (data?['respectGivenBy'] as List?)?.cast<String>() ?? const [];
    _changed();
  }

  void _onUser(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (_stopped) return;
    _balance = (snap.data()?['respectBalance'] as num?)?.toInt() ?? 0;
    _changed();
  }

  /// The Respect step needs a balance of at least 1. If it's empty once
  /// the event exists, ask the server for the one-time onboarding grant;
  /// the server re-checks everything, so a stale cached balance here costs
  /// at most one no-op call.
  void _maybeRequestGrant(OnboardingModuleHost host) {
    final balance = _balance;
    if (_grantRequested ||
        _eventId == null ||
        _respectGiven ||
        balance == null ||
        balance >= 1) {
      return;
    }
    _grantRequested = true;
    _grantCall = 'calling';
    host.repository
        .ensureOnboardingRespect()
        .then((decision) {
          _grantCall = decision;
          if (!_stopped) _changed();
        })
        .catchError((Object e) {
          _grantCall = 'error: $e';
          debugPrint('Onboarding Module 4 Respect grant error: $e');
          // One more try on the next state change.
          _grantRequested = false;
        });
  }

  void _changed() {
    final host = _host;
    if (host == null || _stopped) return;
    host.guidanceChanged();
    if (_completed || _challengeVerified != true || _eventId == null) return;
    if (_respectGiven) {
      _completed = true;
      host.moduleCompleted(this);
      return;
    }
    _maybeRequestGrant(host);
  }

  @override
  List<OnboardingGuidance> get guidance {
    final eventId = _eventId;
    if (_completed ||
        _challengeVerified != true ||
        eventId == null ||
        !_eventSettled ||
        _respectGiven) {
      return const [];
    }
    if (!_eventExplained) {
      return [
        OnboardingGuidance(
          anchorIds: [OnboardingAnchorIds.homeEvent(eventId)],
          message: eventMessage,
          actions: [
            OnboardingGuidanceAction(
              label: 'Next',
              onPressed: () {
                if (_stopped || _eventExplained) return;
                _eventExplained = true;
                _changed();
              },
            ),
          ],
        ),
      ];
    }
    // No Respect to give (grant in flight, or — if the one-time grant was
    // already used — until the daily grant): point at nothing rather than
    // trap the user behind a spotlight on a button that can't work.
    final balance = _balance;
    if (balance == null || balance < 1) return const [];
    return [
      OnboardingGuidance(
        anchorIds: [OnboardingAnchorIds.homeEventRespect(eventId)],
        message: respectMessage,
      ),
    ];
  }

  @override
  void stop() {
    _stopped = true;
    _settleTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  @override
  Map<String, Object?> debugDescribe() => {
    'm4.completed': _completed,
    'm4.challengeB': _competitionId ?? '(resolving)',
    'm4.challengeVerifiedByMetadata': _challengeVerified ?? '(loading)',
    'm4.systemProgress': _systemProgress ?? '(loading)',
    'm4.systemProgressCall': _systemProgressCall,
    'm4.event': !_eventsLoaded
        ? '(loading)'
        : _eventId == null
        ? '(none yet — waiting for the Events pipeline)'
        : '$_eventId batch=$_eventBatchId settled=$_eventSettled',
    'm4.eventExplained': _eventExplained,
    'm4.respectBalance': _balance ?? '(loading)',
    'm4.respectGrantCall': _grantCall,
    'm4.respectGiven (server)': _respectGiven,
  };
}
