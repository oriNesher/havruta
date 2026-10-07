import {challengeDayKey} from "./calendar";
import {ChallengeConfig} from "./model";

/** The participant fields win conditions decide from. */
export interface StandingParticipant {
  uid: string;
  username: string;
  progress: number;
  /** Own finish line (legacy personal races), if any. */
  targetValue: number | null;
  dailyProgress: Record<string, number>;
  eliminatedOnDay: string | null;
  /** Challenge-calendar day they joined on, if known. */
  joinedDay: string | null;
  /** When their progress last changed — the "got there first" tiebreak. */
  updatedAtMillis: number | null;
}

/**
 * Reads a participants/{uid} doc into a StandingParticipant.
 * @param {FirebaseFirestore.DocumentData} data The participant doc's data.
 * @param {ChallengeConfig} challenge The challenge, for its calendar.
 * @return {StandingParticipant} The normalized participant.
 */
export function toStandingParticipant(
  data: FirebaseFirestore.DocumentData,
  challenge: ChallengeConfig
): StandingParticipant {
  const joinedAt = data.joinedAt as FirebaseFirestore.Timestamp | undefined;
  const updatedAt = data.updatedAt as FirebaseFirestore.Timestamp | undefined;
  const rawDaily = (data.dailyProgress ?? {}) as Record<string, unknown>;
  const dailyProgress: Record<string, number> = {};
  for (const [day, amount] of Object.entries(rawDaily)) {
    if (typeof amount === "number") dailyProgress[day] = amount;
  }

  return {
    uid: data.uid,
    username: data.username ?? "Someone",
    progress: typeof data.progress === "number" ? data.progress : 0,
    targetValue: typeof data.targetValue === "number" &&
      data.targetValue > 0 ?
      data.targetValue :
      null,
    dailyProgress,
    eliminatedOnDay: typeof data.eliminatedOnDay === "string" ?
      data.eliminatedOnDay :
      null,
    joinedDay: joinedAt && typeof joinedAt.toMillis === "function" ?
      challengeDayKey(joinedAt.toMillis(), challenge.timeZone) :
      null,
    updatedAtMillis: updatedAt && typeof updatedAt.toMillis === "function" ?
      updatedAt.toMillis() :
      null,
  };
}

/**
 * A participant's share of their race target (0 when there is none).
 * @param {ChallengeConfig} challenge The challenge.
 * @param {StandingParticipant} participant The participant.
 * @return {number} progress / target.
 */
export function targetFraction(
  challenge: ChallengeConfig,
  participant: StandingParticipant
): number {
  const target = participant.targetValue ?? challenge.targetValue;
  return target && target > 0 ? participant.progress / target : 0;
}

/**
 * Orders participants leader-first for the challenge's win condition.
 * Mirrors rankParticipants in lib/competitions/challenge_standings.dart.
 * - firstToTarget: share of target, then got there first.
 * - mostProgress: total, then got there first.
 * - lastStanding: still in, then later elimination, then total.
 * @param {ChallengeConfig} challenge The challenge.
 * @param {StandingParticipant[]} participants Everyone in it.
 * @return {StandingParticipant[]} A new, ranked array.
 */
export function rankStandings(
  challenge: ChallengeConfig,
  participants: StandingParticipant[]
): StandingParticipant[] {
  const firstThere = (a: StandingParticipant, b: StandingParticipant) =>
    (a.updatedAtMillis ?? Infinity) - (b.updatedAtMillis ?? Infinity);

  return [...participants].sort((a, b) => {
    switch (challenge.winCondition) {
    case "firstToTarget":
      return targetFraction(challenge, b) - targetFraction(challenge, a) ||
        firstThere(a, b);
    case "mostProgress":
      return b.progress - a.progress || firstThere(a, b);
    case "lastStanding": {
      const outA = a.eliminatedOnDay;
      const outB = b.eliminatedOnDay;
      if (outA === null && outB !== null) return -1;
      if (outA !== null && outB === null) return 1;
      if (outA !== null && outB !== null && outA !== outB) {
        return outA < outB ? 1 : -1;
      }
      return b.progress - a.progress;
    }
    }
  });
}
