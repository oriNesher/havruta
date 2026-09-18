import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../onboarding_ids.dart';
import '../onboarding_repository.dart';
import '../onboarding_state.dart';
import 'onboarding_module.dart';

enum _InviteState {
  loading,
  missing,
  notOnboarding,
  pending,

  /// Accepted locally, not yet confirmed by the server.
  accepting,
  accepted,
  declined,
  other,
}

/// Module 1 — accept the two onboarding invitations via the normal
/// Notifications screen and invite accept flow.
///
/// Watches only the two onboarding invite docs (by id, verified by their
/// onboarding metadata), so unrelated invitations can never be highlighted
/// or count toward completion. Completes once both are server-confirmed
/// `accepted` — the same batch that creates the user's participant doc.
class AcceptInvitesModule extends OnboardingModule {
  static const homeMessageTwo =
      'You have two Challenge invitations waiting for you. Tap here to see them.';
  static const homeMessageOne =
      'You have one Challenge invitation waiting for you. Tap here to see it.';

  /// One invitation is pointed at a time, rather than both at once: two
  /// cards rarely fit on screen together, and walking through them in order
  /// keeps "there are two of these" explicit in the copy.
  static const firstInviteMessage =
      'This is your first Challenge invitation. Tap Accept to join it.';
  static const secondInviteMessage =
      'Nice — here is your second Challenge invitation. Accept this one too '
      'and we are all set.';

  OnboardingModuleHost? _host;
  final _subscriptions =
      <StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>[];
  final _inviteIds = <OnboardingChallengeKey, String>{};
  final _states = <OnboardingChallengeKey, _InviteState>{};
  bool _stopped = false;
  bool _completed = false;
  bool _repairRequested = false;

  @override
  OnboardingModuleId get id => OnboardingModuleId.acceptInvites;

  @override
  OnboardingUnwind get unwindOnComplete => OnboardingUnwind.toHome;

  @override
  Future<void> prepare(OnboardingModuleHost host) async {
    final ids = await host.repository.startOnboarding();
    if (ids.length != OnboardingChallengeKey.values.length) {
      throw StateError('startOnboarding returned $ids');
    }
    await host.repository.confirmInvitesExist(host.uid, ids.values);
  }

  @override
  void start(OnboardingModuleHost host) {
    _host = host;
    _watch(host);
  }

  Future<void> _watch(OnboardingModuleHost host) async {
    final ids = await host.repository.onboardingInviteIds(host.uid);
    if (_stopped) return;
    for (final entry in ids.entries) {
      _inviteIds[entry.key] = entry.value;
      _states[entry.key] = _InviteState.loading;
      _subscriptions.add(
        host.repository
            .watchInvite(entry.value)
            .listen(
              (snap) => _onInvite(entry.key, snap),
              onError: (Object e) =>
                  debugPrint('Onboarding invite watch error: $e'),
            ),
      );
    }
  }

  void _onInvite(
    OnboardingChallengeKey key,
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final host = _host;
    if (_stopped || host == null) return;

    final state = _classify(snap, host.uid);
    _states[key] = state;

    // Only trust "doesn't exist" from the server, not a cold cache.
    if (state == _InviteState.missing && !snap.metadata.isFromCache) {
      _repair(host);
    }

    host.guidanceChanged();

    final allAccepted =
        _states.length == OnboardingChallengeKey.values.length &&
        _states.values.every((s) => s == _InviteState.accepted);
    if (allAccepted && !_completed) {
      _completed = true;
      host.moduleCompleted(this);
    }
  }

  static _InviteState _classify(
    DocumentSnapshot<Map<String, dynamic>> snap,
    String uid,
  ) {
    final data = snap.data();
    if (!snap.exists || data == null) return _InviteState.missing;
    if (!OnboardingRepository.isOnboardingInviteFor(data, uid)) {
      return _InviteState.notOnboarding;
    }
    switch (data['status']) {
      case 'pending':
        return _InviteState.pending;
      case 'accepted':
        return snap.metadata.hasPendingWrites
            ? _InviteState.accepting
            : _InviteState.accepted;
      case 'declined':
        return _InviteState.declined;
      default:
        return _InviteState.other;
    }
  }

  /// An onboarding invite vanished (e.g. partial cleanup) — startOnboarding
  /// recreates missing records idempotently. Attempted once per start.
  void _repair(OnboardingModuleHost host) {
    if (_repairRequested) return;
    _repairRequested = true;
    host.repository.startOnboarding().catchError((Object e) {
      debugPrint('Onboarding invite repair failed: $e');
      return <OnboardingChallengeKey, String>{};
    });
  }

  @override
  List<OnboardingGuidance> get guidance {
    if (_completed) return const [];
    // Only pending invites are targets: one being accepted (accept dialog
    // submitting, or write not yet confirmed) is deliberately excluded, and
    // a declined/missing one leaves nothing to point at — the guide goes
    // quiet instead of trapping the user behind a spotlight.
    final pendingIds = [
      for (final key in OnboardingChallengeKey.values)
        if (_states[key] == _InviteState.pending) _inviteIds[key]!,
    ];
    if (pendingIds.isEmpty) return const [];

    // "Second" is keyed off one already being dealt with — including an
    // accept still in flight — so the copy doesn't jump back to "first"
    // while a write is settling.
    final anyDone = _states.values.any(
      (s) => s == _InviteState.accepted || s == _InviteState.accepting,
    );

    return [
      OnboardingGuidance(
        anchorIds: [OnboardingAnchorIds.inviteCard(pendingIds.first)],
        message: anyDone ? secondInviteMessage : firstInviteMessage,
      ),
      OnboardingGuidance(
        anchorIds: const [OnboardingAnchorIds.homeNotificationsButton],
        message: pendingIds.length >= 2 ? homeMessageTwo : homeMessageOne,
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
    'completed': _completed,
    for (final key in OnboardingChallengeKey.values)
      'invite.${key.name}': _states[key]?.name ?? '(not watched yet)',
  };
}
