import {ChallengeConfig} from "../model";

export interface FinishClaim {
  /** 1-based finish position across the whole challenge. */
  position: number;
  /** The actor already held a position (a retried trigger), so no write. */
  alreadyClaimed: boolean;
  /** Fields to write to the competition doc, or null for no write. */
  update: Record<string, unknown> | null;
  /** Whether this finish ends the challenge (status -> completed). */
  completes: boolean;
}

/**
 * Decides a race finisher's position and whether they're the winner. Pure
 * so it can run inside the competition-doc transaction in finish.ts —
 * deciding from a count query outside a transaction let two simultaneous
 * finishers both take position 1.
 *
 * Races that had finishers before finisherUids existed only have their
 * won/finishedInPosition events to go on: legacyCompletions (that event
 * count) is frozen into legacyFinisherCount on the first claim, so later
 * positions keep counting from it and no second winner is declared.
 * @param {ChallengeConfig} challenge The challenge, read transactionally.
 * @param {string} actorUid The participant who just reached the target.
 * @param {string[]} participantUids Every current participant.
 * @param {number} legacyCompletions Completion events that already exist;
 *   only consulted on a challenge's first claim.
 * @return {FinishClaim} The decided position and competition-doc write.
 */
export function claimFinish(
  challenge: ChallengeConfig,
  actorUid: string,
  participantUids: string[],
  legacyCompletions: number
): FinishClaim {
  const {legacyFinisherCount} = challenge;
  const existingIndex = challenge.finisherUids.indexOf(actorUid);
  const offset = legacyFinisherCount ??
    (challenge.finisherUids.length === 0 ? legacyCompletions : 0);

  if (existingIndex !== -1) {
    return {
      position: offset + existingIndex + 1,
      alreadyClaimed: true,
      update: null,
      completes: false,
    };
  }

  const finisherUids = [...challenge.finisherUids, actorUid];
  const position = offset + finisherUids.length;
  const update: Record<string, unknown> = {finisherUids};

  if (legacyFinisherCount === null) {
    update.legacyFinisherCount = offset;
  }

  if (position === 1 && challenge.winnerUids.length === 0) {
    update.winnerUids = [actorUid];
    update.winnerUid = actorUid;
  }

  // With a deadline the race ends when time runs out (the finalizer's
  // job); without one it ends once nobody is left racing. Legacy races
  // with pre-claim finishers can't know who those were, so they never
  // auto-complete — the same open-ended behavior they always had.
  const everyoneFinished = participantUids.length >= 2 &&
    participantUids.every((uid) => finisherUids.includes(uid));
  const completes = challenge.endsAt === null && offset === 0 &&
    everyoneFinished;

  if (completes) {
    update.status = "completed";
  }

  return {position, alreadyClaimed: false, update, completes};
}
