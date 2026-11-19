import {ChallengeConfig} from "../challenges/model";

/**
 * Whether removing a participant leaves a Race with nobody still racing.
 * A Race without an end date completes once everyone has finished
 * (claimFinish) — but that's only checked when someone crosses the line,
 * so removing the last runner who hadn't finished must complete it here,
 * or it would stay open forever. Mirrors claimFinish's rule: 2+ remaining,
 * no deadline, and no pre-claim legacy finishers it can't account for.
 * @param {ChallengeConfig} challenge The challenge before the removal.
 * @param {string} removedUid Who's being removed.
 * @return {boolean} True when the race should complete now.
 */
export function raceCompletesOnRemoval(
  challenge: ChallengeConfig,
  removedUid: string
): boolean {
  if (challenge.winCondition !== "firstToTarget" ||
    challenge.endsAt !== null ||
    (challenge.legacyFinisherCount ?? 0) !== 0 ||
    challenge.finisherUids.length === 0) {
    return false;
  }
  const remaining = challenge.participantUids.filter((u) => u !== removedUid);
  return remaining.length >= 2 &&
    remaining.every((u) => challenge.finisherUids.includes(u));
}
