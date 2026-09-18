import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../onboarding_ids.dart';
import '../onboarding_repository.dart';
import '../onboarding_state.dart';
import 'onboarding_module.dart';

/// Module 2 — report progress in Challenge A ("Accept two invitations") and
/// win it, through the normal Home card Add Progress button and dialog.
///
/// Challenge A is identified by its onboarding metadata
/// (`onboardingChallengeKey == acceptInvites` for this user), never by
/// title, and every anchor it targets is keyed by that competition id, so
/// another Challenge's Add Progress control can never be highlighted.
///
/// Completion is read from Firestore only: the user's participant progress
/// must have reached the target *and be server-confirmed* (no pending local
/// write), and the Events pipeline must have written this user's
/// "won"/"finishedInPosition" event for it. Because both are persistent
/// records, a relaunch, navigation, or a module resumed after the win
/// already happened all converge on the same answer.
class ReportProgressModule extends OnboardingModule {
  static const homeMessage =
      "Now that you've accepted two invitations, you can report your progress.";

  /// Shown inside the real Add Progress dialog opened from Challenge A, so
  /// the natural amount to enter is the one that completes the Challenge.
  static String dialogMessage({required int remaining, required int target}) {
    if (remaining == target) {
      return 'You accepted $target invitations — enter $target, then press '
          'and hold to submit.';
    }
    return 'Enter $remaining to reach $target, then press and hold to '
        'submit.';
  }

  OnboardingModuleHost? _host;
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _stopped = false;
  bool _completed = false;

  String? _competitionId;

  /// Null until the competition doc is read.
  bool? _challengeVerified;
  int? _sharedTarget;

  /// Null until the participant doc is read.
  bool? _participantExists;
  int _progress = 0;
  int? _participantTarget;
  bool _progressPending = false;
  bool _progressFromCache = false;

  String? _completionEventType;
  String? _completionBatchId;

  @override
  OnboardingModuleId get id => OnboardingModuleId.reportProgress;

  int? get _target => _participantTarget ?? _sharedTarget;

  /// Refuses to start unless Challenge A really exists as this user's
  /// onboarding challenge and they've joined it (Module 1's outcome).
  @override
  Future<void> prepare(OnboardingModuleHost host) async {
    final competitionId = await host.repository.onboardingCompetitionIdFor(
      host.uid,
      OnboardingChallengeKey.acceptInvites,
    );
    final db = FirebaseFirestore.instance;
    final competition = await db
        .collection('competitions')
        .doc(competitionId)
        .get(const GetOptions(source: Source.server));
    final data = competition.data();
    if (data == null ||
        !OnboardingRepository.isOnboardingChallengeFor(
          data,
          host.uid,
          OnboardingChallengeKey.acceptInvites,
        )) {
      throw StateError('Challenge A ($competitionId) is missing or not ours');
    }
    final participant = await competition.reference
        .collection('participants')
        .doc(host.uid)
        .get(const GetOptions(source: Source.server));
    if (!participant.exists) {
      throw StateError('Not a participant of Challenge A yet (Module 1)');
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
      OnboardingChallengeKey.acceptInvites,
    );
    if (_stopped) return;
    _competitionId = competitionId;
    final repo = host.repository;

    _subscriptions.addAll([
      repo
          .watchCompetition(competitionId)
          .listen(_onCompetition, onError: _onError),
      repo
          .watchParticipant(competitionId, host.uid)
          .listen(_onParticipant, onError: _onError),
      repo
          .watchCompletionEvents(competitionId)
          .listen(_onCompletionEvents, onError: _onError),
    ]);
  }

  void _onError(Object e) => debugPrint('Onboarding Module 2 watch error: $e');

  void _onCompetition(DocumentSnapshot<Map<String, dynamic>> snap) {
    final host = _host;
    if (_stopped || host == null) return;
    final data = snap.data();
    _challengeVerified =
        data != null &&
        OnboardingRepository.isOnboardingChallengeFor(
          data,
          host.uid,
          OnboardingChallengeKey.acceptInvites,
        );
    _sharedTarget = (data?['sharedTargetValue'] as num?)?.toInt();
    _changed();
  }

  void _onParticipant(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (_stopped) return;
    final data = snap.data();
    _participantExists = data != null;
    _progress = (data?['progress'] as num? ?? 0).toInt();
    _participantTarget = (data?['targetValue'] as num?)?.toInt();
    _progressPending = snap.metadata.hasPendingWrites;
    _progressFromCache = snap.metadata.isFromCache;
    _changed();
  }

  void _onCompletionEvents(QuerySnapshot<Map<String, dynamic>> snap) {
    final host = _host;
    if (_stopped || host == null) return;
    _completionEventType = null;
    _completionBatchId = null;
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['actorUid'] != host.uid) continue;
      _completionEventType = data['type'] as String?;
      _completionBatchId = data['batchId'] as String?;
      break;
    }
    _changed();
  }

  /// Target reached as far as the server knows — an optimistic local
  /// increment that hasn't been acknowledged doesn't count.
  bool get _targetReachedOnServer {
    final target = _target;
    return _participantExists == true &&
        !_progressPending &&
        target != null &&
        target > 0 &&
        _progress >= target;
  }

  void _changed() {
    final host = _host;
    if (host == null) return;
    host.guidanceChanged();
    if (_completed || _challengeVerified != true) return;
    if (_targetReachedOnServer && _completionEventType != null) {
      _completed = true;
      host.moduleCompleted(this);
    }
  }

  @override
  List<OnboardingGuidance> get guidance {
    final competitionId = _competitionId;
    final target = _target;
    if (_completed ||
        competitionId == null ||
        _challengeVerified != true ||
        _participantExists != true ||
        target == null ||
        target <= 0) {
      return const [];
    }
    // A report in flight, or the target reached and the pipeline still
    // catching up: nothing to point at. (The Add Progress button itself is
    // gone once progress reaches the target.)
    if (_progressPending || _progress >= target) return const [];

    return [
      OnboardingGuidance(
        anchorIds: [
          OnboardingAnchorIds.addProgressDialogInput(competitionId),
          OnboardingAnchorIds.addProgressDialogCancel(competitionId),
        ],
        message: dialogMessage(remaining: target - _progress, target: target),
      ),
      OnboardingGuidance(
        anchorIds: [OnboardingAnchorIds.addProgressButton(competitionId)],
        message: homeMessage,
      ),
    ];
  }

  @override
  void stop() {
    _stopped = true;
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  @override
  Map<String, Object?> debugDescribe() => {
    'm2.completed': _completed,
    'm2.challengeA': _competitionId ?? '(resolving)',
    'm2.challengeVerifiedByMetadata': _challengeVerified ?? '(loading)',
    'm2.participant': switch (_participantExists) {
      null => '(loading)',
      false => 'MISSING',
      true =>
        '$_progress / ${_target ?? '?'}'
            '${_progressPending ? ' (pending local write)' : ''}'
            '${_progressFromCache ? ' (from cache)' : ''}',
    },
    'm2.targetReachedOnServer': _targetReachedOnServer,
    'm2.completionEvent': _completionEventType == null
        ? '(none yet)'
        : '$_completionEventType batch=$_completionBatchId',
  };
}
