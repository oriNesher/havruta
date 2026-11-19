import {ChallengeConfig} from "../challenges/model";
import {StandingParticipant} from "../challenges/standings";
import {
  decideDeadlineResult,
  Placement,
} from "../challenges/winConditions/deadline";
import {
  Elimination,
  evaluateLastStanding,
} from "../challenges/winConditions/lastStanding";
import {OrganizerError} from "./errors";

/** What ending a challenge early writes and announces. */
export interface EarlyEndPlan {
  /** Competition-doc fields (status, winners, judging cursor). */
  update: Record<string, unknown>;
  /** Last One Standing days that had ended but weren't judged yet. */
  eliminations: Elimination[];
  /** won / finishedInPosition events to announce. */
  placements: Placement[];
  winnerUids: string[];
}

/**
 * Decides the result of an organizer ending a challenge now. Pure.
 * - Race and Most Progress settle exactly as if the end date were now
 *   (decideDeadlineResult): an existing Race winner stands, otherwise the
 *   furthest along wins; Most Progress goes to the highest total.
 * - Last One Standing first judges every day that has already ended (as
 *   the hourly job would); today's unfinished day is ignored, and everyone
 *   still standing shares the win. One that hasn't started yet has no
 *   winner.
 * @param {ChallengeConfig} challenge The challenge, read transactionally.
 * @param {StandingParticipant[]} participants Everyone in it.
 * @param {number} nowMillis The current time.
 * @return {EarlyEndPlan} What to write and announce.
 * @throws {OrganizerError} When the challenge is already over.
 */
export function planEarlyEnd(
  challenge: ChallengeConfig,
  participants: StandingParticipant[],
  nowMillis: number
): EarlyEndPlan {
  if (challenge.status !== "active") {
    throw new OrganizerError("This challenge is already over.");
  }

  if (challenge.winCondition !== "lastStanding") {
    const result = decideDeadlineResult(challenge, participants);
    return {
      update: completedWith(result.winnerUids),
      eliminations: [],
      placements: result.placements,
      winnerUids: result.winnerUids,
    };
  }

  const judged = evaluateLastStanding(challenge, participants, nowMillis);
  const notStarted = !challenge.startsAt ||
    challenge.startsAt.toMillis() > nowMillis;

  let winnerUids: string[];
  if (judged.completes) {
    winnerUids = judged.winnerUids;
  } else if (notStarted) {
    winnerUids = [];
  } else {
    const out = new Set(judged.eliminations.map((e) => e.uid));
    winnerUids = participants
      .filter((p) => p.eliminatedOnDay === null && !out.has(p.uid))
      .map((p) => p.uid);
  }

  return {
    update: {...(judged.update ?? {}), ...completedWith(winnerUids)},
    eliminations: judged.eliminations,
    placements: winnerUids.map((uid) => ({uid, position: 1})),
    winnerUids,
  };
}

/**
 * The fields that mark a challenge completed with these winners.
 * @param {string[]} winnerUids The winners (may be empty).
 * @return {Record<string, unknown>} status, winnerUids, winnerUid.
 */
function completedWith(winnerUids: string[]): Record<string, unknown> {
  return {
    status: "completed",
    winnerUids,
    winnerUid: winnerUids[0] ?? null,
  };
}
