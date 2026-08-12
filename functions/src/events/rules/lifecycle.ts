/**
 * A new participant doc should only create a "joined" event if it isn't the
 * creator's own doc being seeded at competition-creation time (creation only
 * ever seeds the creator; every other doc creation is a genuine join).
 * @param {string} participantUid The uid on the new participant doc.
 * @param {string | undefined} competitionCreatedBy The competition's
 *   creator uid.
 * @return {boolean} True if this is a genuine join.
 */
export function shouldCreateJoinedEvent(
  participantUid: string,
  competitionCreatedBy: string | undefined
): boolean {
  return participantUid !== competitionCreatedBy;
}

/**
 * A deleted participant doc should only create a "left" event if the
 * competition itself still exists — otherwise this deletion is part of
 * tearing down the whole competition, not a participant leaving one that
 * continues.
 * @param {boolean} competitionExists Whether the competition doc still
 *   exists at the time of this deletion.
 * @return {boolean} True if this is a genuine departure.
 */
export function shouldCreateLeftEvent(competitionExists: boolean): boolean {
  return competitionExists;
}
