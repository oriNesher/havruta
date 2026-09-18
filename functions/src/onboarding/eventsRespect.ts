// Pure decision logic for onboarding Module 4 (Events and Respect), kept
// free of Firestore so it can be unit-tested the same way the event rules
// are. The two callables that use it — ensureOnboardingSystemProgress and
// ensureOnboardingRespect — only read documents, hand them to these
// functions inside a transaction, and apply what they decide.

import {
  ONBOARDING_VERSION,
  SYSTEM_USER_UID,
} from "./config";

/**
 * Havruta's progress in Challenge B ("challengeFriends") after Module 4's
 * one scripted action: it has challenged one person — the onboarding user,
 * who accepted its invitation. The target is 2, so this reads "1 / 2".
 */
export const ONBOARDING_SYSTEM_PROGRESS = 1;

/** Respect granted by ensureOnboardingRespect, at most once per user. */
export const ONBOARDING_RESPECT_GRANT = 1;

type Data = FirebaseFirestore.DocumentData | undefined;

/**
 * Checks that Challenge B is genuinely the caller's own onboarding
 * challenge, owned by the system user, with both the caller and the real
 * system user as participants. Identity comes from explicit onboarding
 * metadata and document ownership — never the title.
 * @param {string} uid The calling user's uid.
 * @param {Data} competition Challenge B's competition doc data.
 * @param {Data} systemParticipant Its participants/{SYSTEM_USER_UID} data.
 * @param {Data} callerParticipant Its participants/{uid} data.
 * @return {string | null} Why the preconditions fail, or null if they hold.
 */
export function challengeFriendsProblem(
  uid: string,
  competition: Data,
  systemParticipant: Data,
  callerParticipant: Data
): string | null {
  if (!competition) return "Challenge B does not exist";
  const meta = competition.onboarding;
  if (meta?.isOnboarding !== true) return "not an onboarding challenge";
  if (meta?.onboardingUserId !== uid) return "not this user's onboarding";
  if (meta?.onboardingChallengeKey !== "challengeFriends") {
    return "not the challengeFriends onboarding challenge";
  }
  if (meta?.onboardingVersion !== ONBOARDING_VERSION) {
    return `onboarding version ${meta?.onboardingVersion} is stale`;
  }
  if (competition.createdBy !== SYSTEM_USER_UID) {
    return "not owned by the system user";
  }
  if (competition.status !== "active") return "Challenge B is not active";
  const members = competition.participantUids;
  if (!Array.isArray(members) ||
    !members.includes(uid) ||
    !members.includes(SYSTEM_USER_UID)) {
    return "caller and system user must both be members";
  }
  if (systemParticipant?.uid !== SYSTEM_USER_UID) {
    return "system participant is missing or not the system user";
  }
  if (callerParticipant?.uid !== uid) {
    return "caller has not joined Challenge B";
  }
  return null;
}

/**
 * Whether Havruta's one onboarding progress action still has to happen.
 * It's "already applied" if the server-owned ledger says so, or if the
 * system participant already shows that progress (e.g. the ledger write
 * was lost) — so no retry, relaunch, or concurrent call can ever push it
 * past ONBOARDING_SYSTEM_PROGRESS.
 * @param {Data} ledgerEventsRespect onboarding_state/{uid}.eventsRespect.
 * @param {Data} systemParticipant Challenge B's system participant data.
 * @return {"apply" | "alreadyApplied"} What the callable should do.
 */
export function decideSystemProgress(
  ledgerEventsRespect: Data,
  systemParticipant: Data
): "apply" | "alreadyApplied" {
  if (ledgerEventsRespect?.systemProgressAppliedAt) return "alreadyApplied";
  const progress = (systemParticipant?.progress as number | undefined) ?? 0;
  return progress >= ONBOARDING_SYSTEM_PROGRESS ? "alreadyApplied" : "apply";
}

export type RespectGrantDecision =
  | "grant"
  | "notNeeded"
  | "alreadyGranted"
  | "alreadyGaveRespect"
  | "systemProgressNotApplied";

/**
 * Whether the onboarding Respect grant should fire. It exists only so the
 * tutorial's one real giveRespect can't be blocked by an empty balance:
 * it tops an empty balance up by exactly ONBOARDING_RESPECT_GRANT, once
 * per user ever (the marker lives in the server-only ledger and survives
 * test resets), only once Havruta's onboarding progress exists, and never
 * after the user already gave that Respect.
 * @param {object} input Current state, read transactionally.
 * @param {number} input.balance The caller's respectBalance.
 * @param {Data} input.ledgerRespectGrant onboarding_state/{uid}.respectGrant.
 * @param {boolean} input.systemProgressApplied Havruta's onboarding progress
 *   exists (decideSystemProgress would say "alreadyApplied").
 * @param {boolean} input.alreadyGaveRespect The caller already gave Respect
 *   to Havruta's onboarding progress event.
 * @return {RespectGrantDecision} What the callable should do.
 */
export function decideRespectGrant(input: {
  balance: number;
  ledgerRespectGrant: Data;
  systemProgressApplied: boolean;
  alreadyGaveRespect: boolean;
}): RespectGrantDecision {
  if (input.ledgerRespectGrant?.grantedAt) return "alreadyGranted";
  if (input.alreadyGaveRespect) return "alreadyGaveRespect";
  if (!input.systemProgressApplied) return "systemProgressNotApplied";
  if (input.balance >= 1) return "notNeeded";
  return "grant";
}

/**
 * Whether an event is Havruta's Module 4 progress event: the real
 * "progress" event the Events pipeline wrote for the system user's
 * 0 -> ONBOARDING_SYSTEM_PROGRESS update. Mirrors the client module's match.
 * @param {Data} event An event doc's data from Challenge B.
 * @return {boolean} True for the onboarding progress event.
 */
export function isSystemOnboardingProgressEvent(event: Data): boolean {
  return event?.type === "progress" &&
    event?.actorUid === SYSTEM_USER_UID &&
    event?.metadata?.beforeProgress === 0;
}
