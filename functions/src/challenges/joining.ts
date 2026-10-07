import {challengeDayKey} from "./calendar";
import {ChallengeConfig} from "./model";

/**
 * Why a challenge no longer accepts new participants, or null if it does.
 * One rule for every join path the server controls (invite links); the
 * client hides its invite UI by the same rule.
 * - A finished challenge is closed.
 * - Last One Standing closes once day 1 is over: everyone still in has met
 *   every judged day's minimum, and a later joiner would skip those days.
 *   Joining during day 1 is fine — they're judged on day 1 too.
 * @param {ChallengeConfig} challenge The challenge being joined.
 * @param {number} nowMillis The current time.
 * @return {string | null} A user-facing reason, or null when open.
 */
export function joinClosedReason(
  challenge: ChallengeConfig,
  nowMillis: number
): string | null {
  if (challenge.status !== "active") {
    return "This challenge is no longer active.";
  }
  if (challenge.endsAt && challenge.endsAt.toMillis() <= nowMillis) {
    return "This challenge has ended.";
  }
  if (
    challenge.winCondition === "lastStanding" &&
    challenge.startsAt &&
    challengeDayKey(nowMillis, challenge.timeZone) >
      challengeDayKey(challenge.startsAt.toMillis(), challenge.timeZone)
  ) {
    return "This Last One Standing challenge has already started.";
  }
  return null;
}

/**
 * When joining closes on its own (absent completion), in epoch millis, or
 * Infinity: the end time, or for Last One Standing the end of day 1
 * (approximated as startsAt + 24h — DST can shift it by an hour).
 * @param {ChallengeConfig} challenge The challenge.
 * @return {number} The closing moment.
 */
export function joinClosesAtMillis(challenge: ChallengeConfig): number {
  const endsAt = challenge.endsAt?.toMillis() ?? Infinity;
  const dayOneEnds = challenge.winCondition === "lastStanding" &&
    challenge.startsAt ?
    challenge.startsAt.toMillis() + 24 * 60 * 60 * 1000 :
    Infinity;
  return Math.min(endsAt, dayOneEnds);
}

/**
 * The goal fields a new participant doc gets: everyone shares the
 * challenge's goal, and only a race has a finish line to copy.
 * @param {ChallengeConfig} challenge The challenge being joined.
 * @return {object} goalTitle, unit and (races only) targetValue, to write
 *   on participants/{uid}.
 */
export function sharedGoalFields(
  challenge: ChallengeConfig
): {goalTitle: string; unit: string; targetValue?: number} {
  return {
    goalTitle: challenge.goalTitle,
    unit: challenge.unit,
    ...(challenge.targetValue !== null ?
      {targetValue: challenge.targetValue} :
      {}),
  };
}
