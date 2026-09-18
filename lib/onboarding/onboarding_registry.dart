import 'package:flutter/foundation.dart' show immutable, kDebugMode;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'modules/accept_invites_module.dart';
import 'modules/celebration_trash_talk_module.dart';
import 'modules/create_challenge_module.dart';
import 'modules/events_respect_module.dart';
import 'modules/invite_people_module.dart';
import 'modules/onboarding_module.dart';
import 'modules/report_progress_module.dart';
import 'onboarding_state.dart';

/// What an eligibility rule can look at. Kept to tutorial state for now;
/// a future rule that needs product state (e.g. "has a streak") adds the
/// fact here, fed by the controller, rather than querying on its own.
@immutable
class OnboardingEligibilityContext {
  final OnboardingTutorialState state;
  final OnboardingModuleStatus Function(OnboardingModuleId id) statusOf;

  const OnboardingEligibilityContext({
    required this.state,
    required this.statusOf,
  });

  bool everCompleted(OnboardingModuleId id) =>
      state.progressOf(id).everCompleted;

  Map<String, Object?> dataOf(OnboardingModuleId id) => state.dataOf(id);
}

/// "Should this module currently be surfaced to this user?" — beyond its
/// declared prerequisites.
typedef OnboardingEligibility =
    bool Function(OnboardingEligibilityContext context);

/// How a module presents itself in the Home onboarding checklist.
@immutable
class OnboardingChecklistEntry {
  final String title;

  /// One line.
  final String description;
  final PhosphorIconData icon;
  final bool dismissible;

  const OnboardingChecklistEntry({
    required this.title,
    required this.description,
    required this.icon,
    this.dismissible = true,
  });
}

/// Everything the onboarding system knows about one module. Adding a
/// module means adding an [OnboardingModuleId], implementing its
/// [OnboardingModule], and registering one of these — Home, the checklist
/// and the controller need no module-specific changes.
@immutable
class OnboardingModuleDefinition {
  final OnboardingModuleId id;

  /// Bump when the module teaches something new enough to show again to
  /// users who completed (or dismissed) an earlier version. Only this
  /// module resurfaces; nothing else is replayed.
  final int version;

  final OnboardingModule Function() create;

  /// Null keeps the module out of the checklist (it only ever runs as part
  /// of another flow, e.g. as a [continueWith]).
  final OnboardingChecklistEntry? checklist;

  /// Modules that must have been completed (at any version) first.
  final List<OnboardingModuleId> prerequisites;

  /// Extra contextual rule, checked after [prerequisites].
  final OnboardingEligibility? isEligible;

  /// Runs straight after this module completes, however it was started,
  /// unless already completed or dismissed.
  final OnboardingModuleId? continueWith;

  /// Whether a dismissal also hides later versions. Off by default: a
  /// dismissal is for the version the user saw.
  final bool dismissAllVersions;

  const OnboardingModuleDefinition({
    required this.id,
    required this.version,
    required this.create,
    this.checklist,
    this.prerequisites = const [],
    this.isEligible,
    this.continueWith,
    this.dismissAllVersions = false,
  });

  bool eligibleIn(OnboardingEligibilityContext context) =>
      prerequisites.every(context.everCompleted) &&
      (isEligible?.call(context) ?? true);
}

/// The single list of onboarding modules.
abstract final class OnboardingModuleRegistry {
  static final List<OnboardingModuleDefinition> definitions = [
    OnboardingModuleDefinition(
      id: OnboardingModuleId.acceptInvites,
      version: 1,
      create: AcceptInvitesModule.new,
      checklist: OnboardingChecklistEntry(
        title: 'Join your first Challenges',
        description: 'Accept two invitations and see how joining works.',
        icon: PhosphorIconsFill.envelopeSimpleOpen,
      ),
    ),
    OnboardingModuleDefinition(
      id: OnboardingModuleId.reportProgress,
      version: 1,
      create: ReportProgressModule.new,
      // Challenge A must exist and be joined (checked again in prepare).
      prerequisites: const [OnboardingModuleId.acceptInvites],
      continueWith: OnboardingModuleId.celebrationTrashTalk,
      checklist: OnboardingChecklistEntry(
        title: 'Report progress and win',
        description: 'Log progress, finish a Challenge, and celebrate it.',
        icon: PhosphorIconsFill.trophy,
      ),
    ),
    // Explains the celebration Report Progress's win produces, so it only
    // runs as that module's continuation — on its own there'd be no
    // uncelebrated win to explain.
    OnboardingModuleDefinition(
      id: OnboardingModuleId.celebrationTrashTalk,
      version: 1,
      create: CelebrationTrashTalkModule.new,
      prerequisites: const [OnboardingModuleId.reportProgress],
    ),
    OnboardingModuleDefinition(
      id: OnboardingModuleId.eventsRespect,
      version: 1,
      create: EventsRespectModule.new,
      // Taught in Challenge B, which Accept Invites joins.
      prerequisites: const [OnboardingModuleId.acceptInvites],
      checklist: OnboardingChecklistEntry(
        title: 'Events and Respect',
        description: "See what others are doing and give them Respect.",
        icon: PhosphorIconsFill.handsClapping,
      ),
    ),
    OnboardingModuleDefinition(
      id: OnboardingModuleId.createChallenge,
      version: 1,
      create: CreateChallengeModule.new,
      continueWith: OnboardingModuleId.invitePeople,
      checklist: OnboardingChecklistEntry(
        title: 'Create your own Challenge',
        description: 'Set a goal and a target for you and your friends.',
        icon: PhosphorIconsFill.flag,
      ),
    ),
    OnboardingModuleDefinition(
      id: OnboardingModuleId.invitePeople,
      version: 1,
      create: InvitePeopleModule.new,
      // Teaches on the Challenge Create Challenge tracked — without one
      // there's nothing to invite people to.
      prerequisites: const [OnboardingModuleId.createChallenge],
      isEligible: (context) =>
          context.dataOf(OnboardingModuleId.createChallenge)[
              CreateChallengeModule.competitionIdKey] is String,
      checklist: OnboardingChecklistEntry(
        title: 'Invite people',
        description: 'Bring friends into the Challenge you created.',
        icon: PhosphorIconsFill.userPlus,
      ),
    ),
  ];

  static final Map<OnboardingModuleId, OnboardingModuleDefinition> _byId = {
    for (final definition in definitions) definition.id: definition,
  };

  static OnboardingModuleDefinition of(OnboardingModuleId id) => _byId[id]!;

  /// The module's current version (see [OnboardingModuleDefinition.version]).
  static int versionOf(OnboardingModuleId id) =>
      of(id).version + (kDebugMode ? (debugVersionBumps[id] ?? 0) : 0);

  /// TEMPORARY (debug harness only): in-memory version bumps that simulate
  /// shipping a new module version. Lost on a real app restart. Remove
  /// with lib/debug/onboarding_debug_screen.dart.
  static final Map<OnboardingModuleId, int> debugVersionBumps = {};
}
