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

  /// TEMPORARY: the debug-only onboarding harness button in the Home app
  /// bar. The guide layer keeps it tappable through the spotlight scrim in
  /// debug builds; remove with the harness itself.
  static const debugHarnessButton = 'debug.onboardingHarness';
}

/// Mirrors OnboardingChallengeKey in functions/src/onboarding/config.ts —
/// each value's `.name` is the exact key the backend uses.
enum OnboardingChallengeKey { acceptInvites, challengeFriends }

/// Mirrors onboardingInviteId() in functions/src/onboarding/config.ts.
String onboardingInviteId(String uid, OnboardingChallengeKey key) =>
    'onboarding_invite_${uid}_${key.name}';

/// Mirrors onboardingCompetitionId() in functions/src/onboarding/config.ts.
String onboardingCompetitionId(String uid, OnboardingChallengeKey key) =>
    'onboarding_${uid}_${key.name}';
