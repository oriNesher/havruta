import 'dart:async';

import '../competitions/challenge.dart';

/// A notable moment in the product that leaves no Firestore trace of its
/// own, published so other parts of the app (e.g. onboarding) can react
/// without the screen that caused it knowing who is listening.
sealed class AppSignal {
  const AppSignal();
}

/// The native share sheet was presented for a Trash Talk card. Says nothing
/// about whether anything was actually sent — that isn't observable.
class TrashTalkShareSheetShown extends AppSignal {
  final String competitionId;
  final String? batchId;

  const TrashTalkShareSheetShown({
    required this.competitionId,
    required this.batchId,
  });
}

/// The Create Challenge form's required details (goal + a positive target)
/// became complete or incomplete. Emitted once when the form opens (always
/// incomplete) and then only when completeness flips.
class ChallengeDraftChanged extends AppSignal {
  final bool requiredDetailsComplete;

  const ChallengeDraftChanged({required this.requiredDetailsComplete});
}

/// A Challenge was created from the Create Challenge form — emitted only
/// after every creation write has been acknowledged by the server and the
/// flow has moved on to its Invite step.
class ChallengeCreated extends AppSignal {
  final String competitionId;
  final WinCondition winCondition;

  const ChallengeCreated({
    required this.competitionId,
    required this.winCondition,
  });
}

/// A real invite link for [competitionId] was created by the createInvite
/// callable and then handed to the share sheet ([method] `share`) or put on
/// the clipboard (`copy`). Emitted only after both succeeded; says nothing
/// about whether anyone received it. The link record itself is server-only
/// (challenge_invite_links), so this is the client's only trace of it.
class InviteLinkShared extends AppSignal {
  final String competitionId;
  final String method;

  const InviteLinkShared({required this.competitionId, required this.method});
}

/// The Invite step that follows Challenge creation closed, via Done or back.
class ChallengeInviteStepClosed extends AppSignal {
  final String competitionId;

  const ChallengeInviteStepClosed({required this.competitionId});
}

/// App-wide broadcast of [AppSignal]s. Emitting with no listeners is a
/// no-op, so product code can emit unconditionally.
class AppSignals {
  AppSignals._();
  static final AppSignals instance = AppSignals._();

  final _controller = StreamController<AppSignal>.broadcast();

  Stream<AppSignal> get stream => _controller.stream;

  void emit(AppSignal signal) => _controller.add(signal);
}
