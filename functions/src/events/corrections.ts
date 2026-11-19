import {EventDraft} from "./types";

/** Event types that record a race finish (settled by settleRaceFinish). */
export const COMPLETION_TYPES = ["won", "finishedInPosition"];

/**
 * Whether a participant-doc update is an organizer correction rather than
 * the participant's own report: correctProgress stamps a fresh
 * lastCorrectionId (server-owned in firestore.rules, so a participant
 * can't fake one).
 * @param {FirebaseFirestore.DocumentData} before The doc before the write.
 * @param {FirebaseFirestore.DocumentData} after The doc after the write.
 * @return {boolean} True for an organizer correction.
 */
export function isOrganizerCorrection(
  before: FirebaseFirestore.DocumentData,
  after: FirebaseFirestore.DocumentData
): boolean {
  const id = after.lastCorrectionId;
  return typeof id === "string" && !!id && id !== before.lastCorrectionId;
}

/**
 * The drafts an organizer correction still produces: only a race finish.
 * Crossing the target by correction really does finish the race (and may
 * win it), but a correction isn't the participant doing something, so it
 * fires no progress/ranking/streak events and no push.
 * @param {EventDraft[]} drafts Drafts the rules produced for the write.
 * @return {EventDraft[]} The finish drafts alone.
 */
export function keepForCorrection(drafts: EventDraft[]): EventDraft[] {
  return drafts.filter((d) => COMPLETION_TYPES.includes(d.type));
}
