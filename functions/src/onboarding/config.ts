// Onboarding runs *inside* the real product: two real `competitions` docs
// and two real `competition_invites` docs, owned by a system-managed
// "Havruta" user, using the exact same collections/fields that
// createCompetition/sendCompetitionInvite already write (see
// lib/services/firestore_service.dart). This file is the one place that
// defines what those two challenges are, so later modules (progress
// scripting, cleanup, analytics exclusion) all read from here instead of
// re-deriving titles/targets by hand.
//
// The "Havruta" system user is a synthetic Firestore uid, *not* a real
// Firebase Auth account — there is no password or credential for it to
// leak, and nothing can sign in as it. Every privileged action taken "as"
// this user (creating challenges, sending invites, and later logging
// progress) is an Admin SDK write from inside a Cloud Function, which
// bypasses firestore.rules entirely — the same trust boundary already used
// by createInvite/redeemInvite for the invite-link flow. A real client can
// never write `createdBy`/`fromUid` as this uid: the rules require
// `request.auth.uid` to match those fields, and no client is ever
// authenticated as this uid.

/** Firestore uid used for the system-managed Havruta onboarding user. */
export const SYSTEM_USER_UID = "havruta_system";

/** Display name for the system user, e.g. shown as "Invited by: Havruta". */
export const SYSTEM_USERNAME = "Havruta";

/**
 * Bumped whenever the onboarding challenge definitions below change in a
 * way that should invalidate previously-created instances (e.g. a changed
 * target or unit). Stored on every onboarding record so a future migration
 * can find and rebuild stale instances instead of guessing from content.
 */
export const ONBOARDING_VERSION = 1;

/** Stable identifier for one of the two onboarding challenges. */
export type OnboardingChallengeKey = "acceptInvites" | "challengeFriends";

export interface OnboardingChallengeConfig {
  key: OnboardingChallengeKey;
  title: string;
  description: string;
  goalTitle: string;
  targetValue: number;
  unit: string;
}

/**
 * The two onboarding challenges, as personalGoalChallenge shells owned by
 * the system user. Challenge A ("acceptInvites") is where a new user
 * learns to accept invitations, report progress, win, and see
 * Celebrations/Trash Talk. Challenge B ("challengeFriends") is meant to
 * stay active afterward and later carry a real system-authored progress
 * update through the normal Events pipeline, to teach Events and Respect.
 */
export const ONBOARDING_CHALLENGES: OnboardingChallengeConfig[] = [
  {
    key: "acceptInvites",
    title: "Accept two invitations in Havruta",
    description:
      "Havruta's way of saying hi — accept a couple of invitations to " +
      "see how progress, wins, and Celebrations work.",
    goalTitle: "Accept two invitations",
    targetValue: 2,
    unit: "invitations",
  },
  {
    key: "challengeFriends",
    title: "Challenge two friends in Havruta",
    description:
      "Invite two friends of your own — this one stays active so you " +
      "can see Events and Respect play out for real.",
    goalTitle: "Challenge two friends",
    targetValue: 2,
    unit: "friends",
  },
];

/**
 * Deterministic competitions/{id} document id for one user's instance of
 * one onboarding challenge. Determinism (rather than an auto-generated id
 * looked up by query) is what makes onboarding initialization idempotent:
 * a retry recomputes the same id and finds the same document instead of
 * risking a duplicate.
 * @param {string} uid The new user's uid onboarding is being run for.
 * @param {OnboardingChallengeKey} key Which onboarding challenge.
 * @return {string} The deterministic competition document id.
 */
export function onboardingCompetitionId(
  uid: string,
  key: OnboardingChallengeKey
): string {
  return `onboarding_${uid}_${key}`;
}

/**
 * Deterministic competition_invites/{id} document id for one user's
 * instance of one onboarding challenge. See onboardingCompetitionId for why
 * determinism matters here.
 * @param {string} uid The new user's uid onboarding is being run for.
 * @param {OnboardingChallengeKey} key Which onboarding challenge.
 * @return {string} The deterministic invite document id.
 */
export function onboardingInviteId(
  uid: string,
  key: OnboardingChallengeKey
): string {
  return `onboarding_invite_${uid}_${key}`;
}
