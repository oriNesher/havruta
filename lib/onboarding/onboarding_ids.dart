// Identifiers shared between the onboarding controller/modules and the
// product screens that expose OnboardingAnchors for them.
//
// Screens only reference these ids to say "this real control exists here" —
// they never decide whether a tutorial is running or what it highlights.
// That decision lives entirely in OnboardingController and its modules.

/// Anchor ids placed on real product UI.
abstract final class OnboardingAnchorIds {
  /// The Home screen body. Used as a "Home is the settled, top-most screen"
  /// signal (e.g. before showing the Welcome prompt); never highlighted.
  static const homeScreen = 'home.screen';

  /// The Notifications (bell) button in the Home app bar.
  static const homeNotificationsButton = 'home.notificationsButton';

  /// One pending invitation's whole card on the Notifications screen —
  /// title, who sent it, and its Accept/Decline row. Keyed by invite doc id
  /// so a module targets a specific invitation by identity, never by title.
  static String inviteCard(String inviteId) => 'invite.card.$inviteId';

  /// A Home Challenge card's own Add Progress button. Keyed by competition
  /// id so only one specific Challenge's control can ever be targeted.
  static String addProgressButton(String competitionId) =>
      'home.addProgress.$competitionId';

  /// The Add Progress dialog's amount input + hold-to-submit area, and its
  /// Cancel button, when opened for [competitionId].
  static String addProgressDialogInput(String competitionId) =>
      'addProgress.dialog.input.$competitionId';
  static String addProgressDialogCancel(String competitionId) =>
      'addProgress.dialog.cancel.$competitionId';

  /// The Celebration screen's shareable card and its continue ("Nice!")
  /// button. Keyed by the celebrated batch's batchId — one progress
  /// update's events — so guidance targets one specific celebration.
  static String celebrationCard(String batchId) => 'celebration.card.$batchId';
  static String celebrationContinueButton(String batchId) =>
      'celebration.continue.$batchId';

  /// The Trash Talk screen's shareable card and its Share button, keyed by
  /// the same batchId as the Celebration it was opened from.
  static String trashTalkCard(String batchId) => 'trashTalk.card.$batchId';
  static String trashTalkShareButton(String batchId) =>
      'trashTalk.share.$batchId';

  /// One real Event row in a Home Challenge card's event carousel, and that
  /// row's Give Respect control. Keyed by event doc id, so guidance targets
  /// one specific Event — never "an event in this Challenge".
  static String homeEvent(String eventId) => 'home.event.$eventId';
  static String homeEventRespect(String eventId) =>
      'home.event.respect.$eventId';

  /// TEMPORARY: the debug-only onboarding harness button in the Home app
  /// bar. The guide layer keeps it tappable through the spotlight scrim in
  /// debug builds; remove with the harness itself.
  static const debugHarnessButton = 'debug.onboardingHarness';
}

/// Mirrors OnboardingChallengeKey in functions/src/onboarding/config.ts —
/// each value's `.name` is the exact key the backend uses.
enum OnboardingChallengeKey { acceptInvites, challengeFriends }

/// Mirrors SYSTEM_USER_UID in functions/src/onboarding/config.ts.
const onboardingSystemUserUid = 'havruta_system';

/// Mirrors onboardingInviteId() in functions/src/onboarding/config.ts.
String onboardingInviteId(String uid, OnboardingChallengeKey key) =>
    'onboarding_invite_${uid}_${key.name}';

/// Mirrors onboardingCompetitionId() in functions/src/onboarding/config.ts.
String onboardingCompetitionId(String uid, OnboardingChallengeKey key) =>
    'onboarding_${uid}_${key.name}';
