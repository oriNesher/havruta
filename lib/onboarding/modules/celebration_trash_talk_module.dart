import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../services/app_signals.dart';
import '../onboarding_ids.dart';
import '../onboarding_repository.dart';
import '../onboarding_state.dart';
import 'onboarding_module.dart';

/// Module 3 — the Celebration and Trash Talk that the Module 2 win
/// produces, explained on top of the real screens.
///
/// This module never shows a celebration itself: CelebrationGate pushes
/// the real CelebrationScreen for the win's event batch exactly as it
/// would for anyone, and CelebrationScreen pushes the real TrashTalkScreen.
/// The module only learns the win event's batchId from Firestore and
/// guides the anchors those two screens expose for that batch — so another
/// celebration queued before or after it is never annotated.
///
/// Steps (in memory only: a relaunch re-shows the real celebration from
/// the start, because the batch isn't marked celebrated until that flow
/// finishes, so the explanations simply run again with it):
///   1. Celebration explained — its guidance was shown on the real
///      Celebration screen (or, if the user tapped through before it could
///      settle, on Trash Talk before anything else).
///   2. Trash Talk explained — the user pressed "Next" on its explanation.
///   3. Share resolved — the native share sheet was presented from that
///      Trash Talk screen, or the user chose "Not now".
///
/// If the real celebration ends before that (e.g. dismissed with the system
/// back button), the win batch gets marked celebrated and can't honestly be
/// shown again, so the module completes rather than leave the narrative
/// stuck; debugDescribe records which way it ended.
class CelebrationTrashTalkModule extends OnboardingModule {
  static const celebrationMessage =
      'Big moments in your Challenges become Celebrations. They make '
      'progress and wins feel worth remembering.';
  static const trashTalkMessage =
      'A little friendly rivalry makes Challenges more exciting. Havruta '
      'encourages some Trash Talk to raise the stakes and keep the '
      'competition alive.';
  static const shareMessage =
      'Share it. A little pressure makes the next round more interesting.';

  OnboardingModuleHost? _host;
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _stopped = false;
  bool _completed = false;
  String? _outcome;

  String? _competitionId;
  bool? _challengeVerified;

  /// The user's win (or finish) event in Challenge A, from Firestore.
  String? _winEventId;
  String? _winType;
  String? _batchId;
  bool _winCelebrated = false;
  bool _winLoaded = false;

  bool _celebrationExplained = false;
  bool _trashTalkExplained = false;
  bool _shareResolved = false;

  @override
  OnboardingModuleId get id => OnboardingModuleId.celebrationTrashTalk;

  /// Close Trash Talk once done; CelebrationScreen then closes itself and
  /// CelebrationGate marks the batch celebrated, landing back on Home.
  @override
  OnboardingUnwind get unwindOnComplete => OnboardingUnwind.guidedRoute;

  @override
  void start(OnboardingModuleHost host) {
    _host = host;
    _subscriptions.add(AppSignals.instance.stream.listen(_onSignal));
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
          .watchCompletionEvents(competitionId)
          .listen(_onCompletionEvents, onError: _onError),
    ]);
  }

  void _onError(Object e) => debugPrint('Onboarding Module 3 watch error: $e');

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
    _changed();
  }

  void _onCompletionEvents(QuerySnapshot<Map<String, dynamic>> snap) {
    final host = _host;
    if (_stopped || host == null) return;
    QueryDocumentSnapshot<Map<String, dynamic>>? win;
    for (final doc in snap.docs) {
      if (doc.data()['actorUid'] != host.uid) continue;
      // Prefer one still waiting to be celebrated, should there be several.
      if (win == null || doc.data()['actorCelebrated'] == false) win = doc;
    }
    final data = win?.data();
    _winLoaded = true;
    _winEventId = win?.id;
    _winType = data?['type'] as String?;
    _batchId = data?['batchId'] as String?;
    // Absent means "not celebration-eligible", which a win always is.
    _winCelebrated = data?['actorCelebrated'] == true;
    _changed();
  }

  void _onSignal(AppSignal signal) {
    if (_stopped || _completed) return;
    if (signal is TrashTalkShareSheetShown &&
        _batchId != null &&
        signal.batchId == _batchId) {
      _resolveShare('shareSheetOpened');
    }
  }

  void _resolveShare(String how) {
    if (_shareResolved) return;
    _shareResolved = true;
    _outcome = how;
    _changed();
  }

  void _changed() {
    final host = _host;
    if (host == null) return;
    host.guidanceChanged();
    if (_completed || _challengeVerified != true || _batchId == null) return;

    if (_celebrationExplained && _trashTalkExplained && _shareResolved) {
      _complete(host);
    } else if (_winCelebrated) {
      // The real celebration flow for this batch has run its course.
      _outcome ??= 'celebrationClosedBeforeShareStep';
      _complete(host);
    }
  }

  void _complete(OnboardingModuleHost host) {
    _completed = true;
    host.moduleCompleted(this);
  }

  @override
  List<OnboardingGuidance> get guidance {
    final batchId = _batchId;
    if (_completed ||
        _challengeVerified != true ||
        batchId == null ||
        _winCelebrated) {
      return const [];
    }
    // Only one of these screens is ever the settled top route, so listing
    // all of them lets the guide layer pick whichever is up.
    return [
      // "Nice!" is tappable while the Celebration route is still animating
      // in, before its guidance can settle — if the user got to Trash Talk
      // that way, explain Celebrations there first (the card shows the
      // same celebrated moments) instead of skipping the explanation.
      if (!_celebrationExplained)
        OnboardingGuidance(
          anchorIds: [OnboardingAnchorIds.trashTalkCard(batchId)],
          message: celebrationMessage,
          actions: [
            OnboardingGuidanceAction(
              label: 'Next',
              onPressed: () {
                if (_stopped || _celebrationExplained) return;
                _celebrationExplained = true;
                _changed();
              },
            ),
          ],
        )
      else if (_trashTalkExplained)
        OnboardingGuidance(
          anchorIds: [OnboardingAnchorIds.trashTalkShareButton(batchId)],
          message: shareMessage,
          actions: [
            OnboardingGuidanceAction(
              label: 'Not now',
              primary: false,
              onPressed: () => _resolveShare('skipped'),
            ),
          ],
        )
      else
        OnboardingGuidance(
          anchorIds: [OnboardingAnchorIds.trashTalkCard(batchId)],
          message: trashTalkMessage,
          actions: [
            OnboardingGuidanceAction(
              label: 'Next',
              onPressed: () {
                if (_stopped || _trashTalkExplained) return;
                _trashTalkExplained = true;
                _changed();
              },
            ),
          ],
        ),
      OnboardingGuidance(
        anchorIds: [
          OnboardingAnchorIds.celebrationCard(batchId),
          OnboardingAnchorIds.celebrationContinueButton(batchId),
        ],
        message: celebrationMessage,
      ),
    ];
  }

  @override
  void guidanceShown(OnboardingGuidance shown) {
    final batchId = _batchId;
    if (batchId == null || _celebrationExplained) return;
    if (shown.anchorIds.contains(
      OnboardingAnchorIds.celebrationContinueButton(batchId),
    )) {
      _celebrationExplained = true;
    }
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
    'm3.completed': _completed,
    'm3.outcome': _outcome ?? '(in progress)',
    'm3.challengeA': _competitionId ?? '(resolving)',
    'm3.challengeVerifiedByMetadata': _challengeVerified ?? '(loading)',
    'm3.winEvent': !_winLoaded
        ? '(loading)'
        : _winEventId == null
        ? '(none — Module 2 win not recorded)'
        : '$_winType id=$_winEventId batch=$_batchId '
              'actorCelebrated=$_winCelebrated',
    'm3.celebrationExplained': _celebrationExplained,
    'm3.trashTalkExplained': _trashTalkExplained,
    'm3.shareResolved': _shareResolved,
  };
}
