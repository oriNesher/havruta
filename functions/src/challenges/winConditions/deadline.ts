import {ChallengeConfig} from "../model";
import {
  rankStandings,
  StandingParticipant,
  targetFraction,
} from "../standings";

export interface Placement {
  uid: string;
  /** 1-based; tied winners all hold position 1. */
  position: number;
}

export interface DeadlineResult {
  winnerUids: string[];
  /**
   * Who gets a won/finishedInPosition event now. Race finishers already
   * got theirs when they crossed the target, so a race only places a
   * deadline winner nobody had announced yet.
   */
  placements: Placement[];
}

/**
 * Decides a firstToTarget or mostProgress challenge's result once its
 * endsAt has passed. (lastStanding is settled by evaluateLastStanding,
 * which also handles its end date.)
 * - mostProgress: most total progress wins; equal totals go to whoever
 *   got there first. Nobody logged anything: no winner.
 * - firstToTarget: an existing winner stands. Otherwise the closest to
 *   the target wins (got there first breaks ties); nobody started: no
 *   winner.
 * @param {ChallengeConfig} challenge The challenge, read transactionally.
 * @param {StandingParticipant[]} participants Everyone in it.
 * @return {DeadlineResult} The winners and the placements to announce.
 */
export function decideDeadlineResult(
  challenge: ChallengeConfig,
  participants: StandingParticipant[]
): DeadlineResult {
  const ranked = rankStandings(challenge, participants);

  if (challenge.winCondition === "firstToTarget") {
    if (challenge.winnerUids.length > 0) {
      return {winnerUids: challenge.winnerUids, placements: []};
    }
    const leader = ranked[0];
    if (!leader || targetFraction(challenge, leader) <= 0) {
      return {winnerUids: [], placements: []};
    }
    return {
      winnerUids: [leader.uid],
      placements: [{uid: leader.uid, position: 1}],
    };
  }

  const scored = ranked.filter((p) => p.progress > 0);
  if (scored.length === 0) return {winnerUids: [], placements: []};

  // Only an exact tie on both total and the moment it was reached (two
  // writes landing in the same millisecond) shares the win.
  const top = scored[0];
  const winners = scored.filter((p) => p.progress === top.progress &&
    p.updatedAtMillis === top.updatedAtMillis);

  return {
    winnerUids: winners.map((p) => p.uid),
    placements: scored.map((p, index) => ({
      uid: p.uid,
      position: index < winners.length ? 1 : index + 1,
    })),
  };
}
