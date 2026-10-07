import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/app_signals.dart';
import '../onboarding_ids.dart';
import '../onboarding_state.dart';
import 'onboarding_module.dart';

/// Module 5 — Create Your Own Challenge, taught on the real Home button and
/// the real Create Challenge form.
///
/// Steps (all in memory — a relaunch starts again from the Home button,
/// which is harmless because nothing is created until the form submits):
///   1. Home's Create Challenge button.
///   2. Mode selector — held back until the user's first touch on the
///      form, then "choose how it's won" + the three modes explained. The
///      selector stays live; any mode is fine.
///   3. Required details — non-modal, so "Add more details" stays fully
///      usable.
///   4. Once the form reports its required details complete
///      ([ChallengeDraftChanged]), the submit button — also non-modal.
///
/// Done when the form reports a real creation ([ChallengeCreated], emitted
/// only after the server acknowledged every write and the flow moved on to
/// its Invite step) and the server confirms that Challenge exists as one
/// this user created. Its id is persisted as module data
/// ([competitionIdKey]) before completing, which is how Module 6 knows
/// which Challenge to teach inviting on.
///
/// Recovery: [startedAtKey] records when this module first started. If a
/// creation happened but its id never reached the tutorial state (killed
/// mid-flight), start() finds the first Challenge this user created after
/// that moment and completes with it rather than asking for another one.
/// Challenges that already existed before the module started never match.
class CreateChallengeModule extends OnboardingModule {
  static const competitionIdKey = 'competitionId';
  static const startedAtKey = 'startedAtMs';

  static const homeMessage =
      "You've seen how a Challenge works. Now it's time to create one of "
      'your own.';
  static const typeMessage =
      'First, choose how your Challenge is won.';
  static const typeExplainedMessage =
      'Race: first to reach the target wins. Last One Standing: hit a daily '
      "minimum every day — miss one and you're out. Most Progress: whoever "
      "does the most by the end date wins. We recommend starting with Race — "
      "it's the simplest way to get going.";
  static const essentialsMessage =
      'Start with the essentials. The main Challenge details are required; '
      'everything under "Add more details" is optional, there when you want '
      'more control.';
  static const submitMessage =
      "That's enough to start. Everything else is optional — editing a "
      "Challenge after it's created is coming soon. Tap Create Challenge "
      "when you're ready.";

  OnboardingModuleHost? _host;
  StreamSubscription<AppSignal>? _signals;
  bool _stopped = false;
  bool _completed = false;

  bool _typeIntroduced = false;
  bool _typeExplained = false;
  bool _essentialsAcknowledged = false;
  bool _requiredComplete = false;
  bool _submitAcknowledged = false;

  /// A creation is being confirmed with the server; nothing is shown
  /// meanwhile so no spotlight lingers over the screen transition.
  String? _confirming;
  String _recovery = '(not run)';

  @override
  OnboardingModuleId get id => OnboardingModuleId.createChallenge;

  @override
  void start(OnboardingModuleHost host) {
    _host = host;
    _signals = AppSignals.instance.stream.listen(_onSignal);

    final data = host.moduleData(id);
    final startedAt = data[startedAtKey];
    final knownId = data[competitionIdKey];
    if (startedAt is! int) {
      host.saveModuleData(id, {
        startedAtKey: DateTime.now().millisecondsSinceEpoch,
      });
    }
    if (knownId is String) {
      _recovery = 'persisted id $knownId';
      unawaited(_confirmAndComplete(knownId));
    } else if (startedAt is int) {
      unawaited(_recover(host, startedAt));
    } else {
      _recovery = '(fresh start — nothing to recover)';
    }
  }

  Future<void> _recover(OnboardingModuleHost host, int startedAt) async {
    _recovery = 'looking for a Challenge created after $startedAt';
    try {
      final found = await host.repository.findOwnChallengeCreatedSince(
        host.uid,
        startedAt,
      );
      if (_stopped) return;
      _recovery = found == null ? 'none found' : 'recovered $found';
      if (found != null) await _confirmAndComplete(found);
    } catch (e) {
      _recovery = 'error: $e';
      debugPrint('Onboarding Module 5 recovery error: $e');
    }
  }

  void _onSignal(AppSignal signal) {
    if (_stopped || _completed) return;
    switch (signal) {
      case ChallengeDraftChanged(:final requiredDetailsComplete):
        if (_requiredComplete == requiredDetailsComplete) return;
        _requiredComplete = requiredDetailsComplete;
        _host?.guidanceChanged();
      case ChallengeCreated(:final competitionId):
        // Persisted before anything else: from here on a relaunch recovers
        // this exact Challenge instead of asking for another one.
        _host?.saveModuleData(id, {competitionIdKey: competitionId});
        unawaited(_confirmAndComplete(competitionId));
      default:
        break;
    }
  }

  /// Retries briefly: the signal arrives right after the creation writes
  /// were acknowledged, and a flaky network shouldn't strand the module.
  Future<void> _confirmAndComplete(String competitionId) async {
    final host = _host;
    if (host == null || _completed) return;
    _confirming = competitionId;
    host.guidanceChanged();
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: attempt));
      }
      if (_stopped || _completed) return;
      final confirmed = await host.repository.confirmOwnChallenge(
        competitionId,
        host.uid,
      );
      if (_stopped || _completed) return;
      if (confirmed == true) {
        host.saveModuleData(id, {competitionIdKey: competitionId});
        _completed = true;
        host.moduleCompleted(this);
        return;
      }
      if (confirmed == false) {
        // Deleted, or not a Challenge this user created: never counts.
        debugPrint('Onboarding Module 5: $competitionId is not ours/missing');
        break;
      }
    }
    if (_stopped) return;
    _confirming = null;
    host.guidanceChanged();
  }

  @override
  List<OnboardingGuidance> get guidance {
    if (_completed || _confirming != null) return const [];
    return [
      // On the Create Challenge form (only one of these at a time).
      if (!_typeExplained)
        OnboardingGuidance(
          anchorIds: const [OnboardingAnchorIds.createChallengeTypeSelector],
          message: _typeIntroduced ? typeExplainedMessage : typeMessage,
          waitForUserTouch: !_typeIntroduced,
          actions: [
            OnboardingGuidanceAction(
              label: _typeIntroduced ? 'Got it' : 'Next',
              onPressed: () => _advance(() {
                if (_typeIntroduced) {
                  _typeExplained = true;
                } else {
                  _typeIntroduced = true;
                }
              }),
            ),
          ],
        )
      else if (!_requiredComplete)
        OnboardingGuidance(
          anchorIds: const [OnboardingAnchorIds.createChallengeRequiredDetails],
          message: _essentialsAcknowledged ? '' : essentialsMessage,
          modal: false,
          actions: [
            if (!_essentialsAcknowledged)
              OnboardingGuidanceAction(
                label: 'Got it',
                onPressed: () => _advance(() => _essentialsAcknowledged = true),
              ),
          ],
        )
      else
        OnboardingGuidance(
          anchorIds: const [OnboardingAnchorIds.createChallengeSubmit],
          message: _submitAcknowledged ? '' : submitMessage,
          modal: false,
          actions: [
            if (!_submitAcknowledged)
              OnboardingGuidanceAction(
                label: 'Got it',
                onPressed: () => _advance(() => _submitAcknowledged = true),
              ),
          ],
        ),
      // On Home.
      const OnboardingGuidance(
        anchorIds: [OnboardingAnchorIds.homeCreateChallengeButton],
        message: homeMessage,
      ),
    ];
  }

  void _advance(VoidCallback change) {
    if (_stopped || _completed) return;
    change();
    _host?.guidanceChanged();
  }

  @override
  void stop() {
    _stopped = true;
    _signals?.cancel();
    _signals = null;
  }

  @override
  Map<String, Object?> debugDescribe() {
    final data = _host?.moduleData(id) ?? const {};
    final startedAt = data[startedAtKey];
    return {
      'm5.completed': _completed,
      'm5.startedAt': startedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(startedAt).toIso8601String()
          : '(not set)',
      'm5.trackedChallenge': data[competitionIdKey] ?? '(none yet)',
      'm5.confirming': _confirming ?? '—',
      'm5.recovery': _recovery,
      'm5.steps':
          'typeIntroduced=$_typeIntroduced typeExplained=$_typeExplained '
          'essentialsAck=$_essentialsAcknowledged '
          'requiredComplete=$_requiredComplete submitAck=$_submitAcknowledged',
    };
  }
}
