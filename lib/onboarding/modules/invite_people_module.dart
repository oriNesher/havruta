import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../services/app_signals.dart';
import '../onboarding_anchor.dart';
import '../onboarding_ids.dart';
import '../onboarding_state.dart';
import 'create_challenge_module.dart';
import 'onboarding_module.dart';

/// Module 6 — Invite People, taught on the real invite UI of the Challenge
/// Module 5 tracked (its persisted competition id; never a title).
///
/// That UI is the Invite step creation lands on, and — the same two
/// widgets — the Challenge's details screen, which is how the module picks
/// up again after a relaunch or after the Invite step was left: Home's
/// card for that Challenge is highlighted, and the steps continue there.
///
/// Steps:
///   1. Search for existing users — "Next" to move on (in memory).
///   2. Invite link card; the search area stays pressable too.
///   3. Once an invitation method was used, the Invite step's Done button.
///
/// "Used an invitation method" is only ever a real, confirmed result:
///   * an existing user was invited — a competition_invites doc from this
///     user for this Challenge, confirmed by the server (in any status, so
///     it still counts once accepted/declined), or
///   * the link was shared — [InviteLinkShared], emitted only after the
///     createInvite callable succeeded and the link reached the share sheet
///     or clipboard. The link record is server-only, so that's persisted as
///     module data ([linkSharedKey]) to survive a relaunch.
///
/// Done once a method was used and the server confirms the Challenge still
/// exists as this user's — after the Invite step closes (Done/back) if the
/// method was used while it was open, straight away otherwise (e.g. on
/// resume, when that step no longer exists). Navigation is left to the
/// product: Done already returns Home.
class InvitePeopleModule extends OnboardingModule {
  static const linkSharedKey = 'linkSharedFor';

  static const searchMessage =
      'Already know someone on Havruta? Search here to invite them directly.';
  static const linkMessage =
      "For friends who aren't on Havruta yet, share an invite link. They can "
      'join the Challenge from the link.';
  static const doneMessage =
      "You're ready. Tap Done to finish setting up your Challenge.";
  static const openChallengeMessage =
      'Open your new Challenge to invite people to it.';

  OnboardingModuleHost? _host;
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _stopped = false;
  bool _completed = false;

  String? _competitionId;
  String _resolution = '(resolving)';

  bool _sentInvitesLoaded = false;
  int _confirmedSentInvites = 0;
  bool _linkShared = false;

  bool _searchAcknowledged = false;

  /// Decided once, when an invitation method is first seen: whether it
  /// happened with the Invite step (and its Done button) open.
  bool? _waitForInviteStepClose;
  bool _inviteStepClosed = false;
  bool _confirming = false;

  @override
  OnboardingModuleId get id => OnboardingModuleId.invitePeople;

  bool get _inviteUsed => _confirmedSentInvites > 0 || _linkShared;

  /// Only reached when started on its own (e.g. from the Home checklist) —
  /// as Create Challenge's continuation it starts directly. Refuses unless
  /// the tracked Challenge still exists as one this user created, so it
  /// never starts with nothing to point at.
  @override
  Future<void> prepare(OnboardingModuleHost host) async {
    final known = host.moduleData(
      OnboardingModuleId.createChallenge,
    )[CreateChallengeModule.competitionIdKey];
    if (known is! String) {
      throw StateError('No Challenge tracked by Create Challenge');
    }
    final confirmed = await host.repository.confirmOwnChallenge(
      known,
      host.uid,
    );
    if (confirmed != true) {
      throw StateError('Tracked Challenge $known is missing or unreachable');
    }
  }

  @override
  void start(OnboardingModuleHost host) {
    _host = host;
    _subscriptions.add(AppSignals.instance.stream.listen(_onSignal));
    unawaited(_watch(host));
  }

  Future<void> _watch(OnboardingModuleHost host) async {
    final competitionId = await _resolveChallenge(host);
    if (_stopped || competitionId == null) return;
    _competitionId = competitionId;
    _linkShared = host.moduleData(id)[linkSharedKey] == competitionId;
    _subscriptions.add(
      host.repository
          .watchSentInvites(competitionId, host.uid)
          .listen(_onSentInvites, onError: _onError),
    );
    _changed();
  }

  /// Module 5's persisted id, or — if that never got saved — the same
  /// creator + creation-time recovery Module 5 uses.
  Future<String?> _resolveChallenge(OnboardingModuleHost host) async {
    final created = host.moduleData(OnboardingModuleId.createChallenge);
    final known = created[CreateChallengeModule.competitionIdKey];
    if (known is String) {
      _resolution = 'from Module 5';
      return known;
    }
    final startedAt = created[CreateChallengeModule.startedAtKey];
    if (startedAt is! int) {
      _resolution = 'no Challenge tracked (Module 5 never started)';
      host.guidanceChanged();
      return null;
    }
    try {
      final found = await host.repository.findOwnChallengeCreatedSince(
        host.uid,
        startedAt,
      );
      if (found != null) {
        host.saveModuleData(OnboardingModuleId.createChallenge, {
          CreateChallengeModule.competitionIdKey: found,
        });
      }
      _resolution = found == null
          ? 'no Challenge created since Module 5 started'
          : 'recovered by creator + creation time';
      return found;
    } catch (e) {
      _resolution = 'error: $e';
      debugPrint('Onboarding Module 6 resolve error: $e');
      return null;
    } finally {
      if (!_stopped) host.guidanceChanged();
    }
  }

  void _onError(Object e) => debugPrint('Onboarding Module 6 watch error: $e');

  void _onSentInvites(QuerySnapshot<Map<String, dynamic>> snap) {
    if (_stopped) return;
    _sentInvitesLoaded = true;
    _confirmedSentInvites = snap.docs
        .where((doc) => !doc.metadata.hasPendingWrites)
        .length;
    _changed();
  }

  void _onSignal(AppSignal signal) {
    final competitionId = _competitionId;
    if (_stopped || _completed || competitionId == null) return;
    switch (signal) {
      case InviteLinkShared(competitionId: final shared)
          when shared == competitionId:
        if (!_linkShared) {
          _linkShared = true;
          _host?.saveModuleData(id, {linkSharedKey: competitionId});
        }
        _changed();
      case ChallengeInviteStepClosed(competitionId: final closed)
          when closed == competitionId:
        _inviteStepClosed = true;
        _changed();
      default:
        break;
    }
  }

  void _changed() {
    final host = _host;
    final competitionId = _competitionId;
    if (host == null || _stopped) return;
    host.guidanceChanged();
    if (_completed || competitionId == null || !_inviteUsed) return;
    _waitForInviteStepClose ??= OnboardingAnchorRegistry.instance.isMounted(
      OnboardingAnchorIds.challengeInviteDone(competitionId),
    );
    if (_waitForInviteStepClose! && !_inviteStepClosed) return;
    unawaited(_confirmAndComplete(host, competitionId));
  }

  Future<void> _confirmAndComplete(
    OnboardingModuleHost host,
    String competitionId,
  ) async {
    if (_confirming || _completed) return;
    _confirming = true;
    host.guidanceChanged();
    try {
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
          _completed = true;
          host.moduleCompleted(this);
          return;
        }
        if (confirmed == false) {
          debugPrint('Onboarding Module 6: $competitionId no longer exists');
          return;
        }
      }
    } finally {
      _confirming = false;
      if (!_stopped) host.guidanceChanged();
    }
  }

  @override
  List<OnboardingGuidance> get guidance {
    final competitionId = _competitionId;
    if (_completed ||
        _confirming ||
        competitionId == null ||
        !_sentInvitesLoaded) {
      return const [];
    }
    final search = OnboardingAnchorIds.inviteSearch(competitionId);
    final link = OnboardingAnchorIds.inviteLink(competitionId);
    return [
      if (_inviteUsed)
        OnboardingGuidance(
          anchorIds: [OnboardingAnchorIds.challengeInviteDone(competitionId)],
          message: doneMessage,
        )
      else if (!_searchAcknowledged)
        OnboardingGuidance(
          anchorIds: [search],
          message: searchMessage,
          actions: [
            OnboardingGuidanceAction(
              label: 'Next',
              onPressed: () {
                if (_stopped || _searchAcknowledged) return;
                _searchAcknowledged = true;
                _host?.guidanceChanged();
              },
            ),
          ],
        )
      else
        OnboardingGuidance(
          anchorIds: [link],
          passThroughAnchorIds: [search],
          message: linkMessage,
        ),
      // Anywhere else: lead back to this Challenge's invite UI.
      if (!_inviteUsed)
        OnboardingGuidance(
          anchorIds: [OnboardingAnchorIds.homeChallengeCard(competitionId)],
          message: openChallengeMessage,
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
    'm6.completed': _completed,
    'm6.challenge': _competitionId ?? '(none)',
    'm6.challengeResolution': _resolution,
    'm6.sentInvites (server-confirmed)': _sentInvitesLoaded
        ? _confirmedSentInvites
        : '(loading)',
    'm6.linkShared': _linkShared,
    'm6.invitationMethodUsed': _inviteUsed,
    'm6.searchAcknowledged': _searchAcknowledged,
    'm6.waitForInviteStepClose': _waitForInviteStepClose ?? '(undecided)',
    'm6.inviteStepClosed': _inviteStepClosed,
    'm6.confirming': _confirming,
  };
}
