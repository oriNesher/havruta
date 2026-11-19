import {ChallengeConfig} from "../challenges/model";
import {StandingParticipant} from "../challenges/standings";
import {OrganizerError} from "./errors";

/**
 * Validates an organizer overruling a Last One Standing elimination (a
 * wrong one: they did the work but it wasn't logged in time, say). Pure.
 * Reinstating clears eliminatedOnDay, nothing else: days already judged
 * stay judged — the evaluator only ever moves forward from
 * lastEvaluatedDay, and never judged them while they were out — so they're
 * simply judged again from the next unjudged day, like everyone still in.
 * Only while the challenge runs: an elimination that ended it (crowning
 * the last one standing) has already been announced and stays final.
 * @param {ChallengeConfig} challenge The challenge, read transactionally.
 * @param {StandingParticipant} participant The eliminated participant.
 * @return {{day: string}} The elimination being overruled.
 * @throws {OrganizerError} When there's nothing to reinstate.
 */
export function planReinstatement(
  challenge: ChallengeConfig,
  participant: StandingParticipant
): {day: string} {
  if (challenge.winCondition !== "lastStanding") {
    throw new OrganizerError(
      "Only Last One Standing challenges eliminate anyone.");
  }
  if (challenge.status !== "active") {
    throw new OrganizerError(
      "This challenge is over; its eliminations are final.");
  }
  if (participant.eliminatedOnDay === null) {
    throw new OrganizerError(`${participant.username} is still in.`);
  }
  return {day: participant.eliminatedOnDay};
}
