import {addDays, challengeDayKey} from "./calendar";
import {ChallengeConfig} from "./model";
import {StandingParticipant} from "./standings";

// The Aggressor Badge: each challenge has at most one holder — whoever has
// been pushing hardest over the last few challenge days. Decided only on
// the server (see settleAggressor); the client mirrors the scoring for
// display in lib/competitions/aggressor.dart — keep the two in sync.

/** How many challenge days (today included) the badge looks back over. */
export const AGGRESSOR_WINDOW_DAYS = 3;

/** One participant's standing for the badge. */
export interface AggressorScore {
  uid: string;
  /** Progress logged across their eligible window days. */
  windowTotal: number;
  /**
   * Window days they could compete on — on or after both the day they
   * joined and the challenge's first day. Never less than 1.
   */
  eligibleDays: number;
  /** When their progress last changed — the "got there first" tiebreak. */
  updatedAtMillis: number | null;
}

export interface AggressorDecision {
  /** Who should hold the badge now; null when it's vacant. */
  holderUid: string | null;
  /** Every eligible participant's score, in input order. */
  scores: AggressorScore[];
}

/**
 * The challenge days the badge currently looks at, newest first: today
 * and the days before it, on the challenge's own calendar. Calendar days
 * rather than a rolling 72 hours, because dailyProgress (one bucket per
 * challenge day) is the only time-resolved progress data there is.
 * @param {ChallengeConfig} challenge The challenge, for its time zone.
 * @param {number} nowMillis The current time.
 * @return {string[]} The window's day keys (YYYY-MM-DD), newest first.
 */
export function aggressorWindow(
  challenge: ChallengeConfig,
  nowMillis: number
): string[] {
  const today = challengeDayKey(nowMillis, challenge.timeZone);
  return Array.from(
    {length: AGGRESSOR_WINDOW_DAYS},
    (_, back) => addDays(today, -back)
  );
}

/**
 * Whether a challenge has an Aggressor Badge at all: only while it's
 * running, and not for legacy personal races (each participant's target
 * is client-writable there, so there's no fair common scale) or onboarding
 * challenges (the scripted system user would win it mid-tutorial).
 * @param {ChallengeConfig} challenge The challenge.
 * @param {boolean} isOnboarding Whether it's an onboarding challenge
 *   (competition.onboarding.isOnboarding).
 * @return {boolean} True if the badge should be evaluated.
 */
export function aggressorApplies(
  challenge: ChallengeConfig,
  isOnboarding: boolean
): boolean {
  return challenge.status === "active" &&
    !challenge.isLegacyPersonal &&
    !isOnboarding;
}

/**
 * Scores one participant: their progress over the window days they could
 * compete on, and how many days that is.
 * @param {ChallengeConfig} challenge The challenge.
 * @param {StandingParticipant} participant The participant.
 * @param {string[]} windowDays The window, from aggressorWindow.
 * @return {AggressorScore} Their score.
 */
export function scoreAggressor(
  challenge: ChallengeConfig,
  participant: StandingParticipant,
  windowDays: string[]
): AggressorScore {
  const startDay = challenge.startsAt ?
    challengeDayKey(challenge.startsAt.toMillis(), challenge.timeZone) :
    null;
  const eligible = windowDays.filter((day) =>
    (participant.joinedDay === null || participant.joinedDay <= day) &&
    (startDay === null || startDay <= day));

  return {
    uid: participant.uid,
    windowTotal: eligible.reduce(
      (sum, day) => sum + Math.max(0, participant.dailyProgress[day] ?? 0),
      0
    ),
    // A joinedAt in the future (it's client-written) or a challenge that
    // hasn't started still counts as one day, never a divide by zero.
    eligibleDays: Math.max(1, eligible.length),
    updatedAtMillis: participant.updatedAtMillis,
  };
}

/**
 * Orders two scores by progress per eligible day, highest first. Cross-
 * multiplied rather than divided, so equal rates compare as exactly equal.
 *
 * There's no further normalization against goal size: every participant
 * in a challenge shares one goal, one unit and one target, so dividing by
 * it would scale everyone alike and never change who leads.
 * @param {AggressorScore} a One score.
 * @param {AggressorScore} b The other.
 * @return {number} Negative when a ranks ahead of b, 0 when tied.
 */
export function compareAggressorRate(
  a: AggressorScore,
  b: AggressorScore
): number {
  return b.windowTotal * a.eligibleDays - a.windowTotal * b.eligibleDays;
}

/**
 * Decides who holds the badge right now. Pure, so the settling transaction
 * and tests share one definition.
 * - The highest progress per eligible window day holds it.
 * - Eliminated participants can't hold it; race finishers can.
 * - Tied at the top: the current holder keeps it if they're among the
 *   tied; otherwise whoever got there first, then lowest uid.
 * - Nobody with any progress in the window, or fewer than 2 participants:
 *   vacant.
 * @param {ChallengeConfig} challenge The challenge.
 * @param {StandingParticipant[]} participants Everyone in it.
 * @param {string | null} currentHolderUid Who holds it now, if anyone.
 * @param {number} nowMillis The current time.
 * @return {AggressorDecision} The holder and everyone's scores.
 */
export function decideAggressor(
  challenge: ChallengeConfig,
  participants: StandingParticipant[],
  currentHolderUid: string | null,
  nowMillis: number
): AggressorDecision {
  const windowDays = aggressorWindow(challenge, nowMillis);
  const scores = participants
    .filter((p) => !!p.uid && p.eliminatedOnDay === null)
    .map((p) => scoreAggressor(challenge, p, windowDays));

  if (participants.length < 2 || scores.length === 0) {
    return {holderUid: null, scores};
  }

  const best = [...scores].sort(compareAggressorRate)[0];
  if (best.windowTotal <= 0) return {holderUid: null, scores};

  const tied = scores.filter((s) => compareAggressorRate(s, best) === 0);
  if (tied.some((s) => s.uid === currentHolderUid)) {
    return {holderUid: currentHolderUid, scores};
  }

  const [first] = [...tied].sort((a, b) =>
    (a.updatedAtMillis ?? Infinity) - (b.updatedAtMillis ?? Infinity) ||
    (a.uid < b.uid ? -1 : a.uid > b.uid ? 1 : 0));
  return {holderUid: first.uid, scores};
}
