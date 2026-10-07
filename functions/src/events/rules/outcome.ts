import {EventDraft} from "../types";

/** The participant fields outcome events need. */
export interface OutcomeParticipant {
  uid: string;
  username: string;
}

/**
 * Everyone in the challenge but the actor.
 * @param {OutcomeParticipant[]} participants Everyone in the challenge.
 * @param {string} actorUid The event's actor.
 * @return {string[]} The event's recipients.
 */
function othersThan(
  participants: OutcomeParticipant[],
  actorUid: string
): string[] {
  return participants.map((p) => p.uid).filter((uid) => uid !== actorUid);
}

/**
 * Creates an "eliminated" event per participant knocked out of a Last One
 * Standing challenge, sent to everyone else. Not celebration-eligible:
 * it's news for the others, not a moment for the person who's out.
 * @param {string} competitionTitle The challenge's title.
 * @param {OutcomeParticipant[]} participants Everyone in the challenge.
 * @param {Array<{uid: string, day: string, dayNumber: number}>}
 *   eliminations Who went out, and on which day.
 * @return {EventDraft[]} The eliminated event drafts to persist.
 */
export function detectEliminationEvents(
  competitionTitle: string,
  participants: OutcomeParticipant[],
  eliminations: {uid: string; day: string; dayNumber: number}[]
): EventDraft[] {
  return eliminations.map((elimination) => {
    const actor = participants.find((p) => p.uid === elimination.uid);
    return {
      type: "eliminated",
      recipients: othersThan(participants, elimination.uid),
      target: {kind: "create"},
      payload: {
        competitionTitle,
        actorUid: elimination.uid,
        actorUsername: actor?.username ?? "Someone",
        targetUid: null,
        targetUsername: null,
        metadata: {
          day: elimination.day,
          dayNumber: elimination.dayNumber,
        },
      },
    };
  });
}

/**
 * Creates the end-of-challenge "won" / "finishedInPosition" events once a
 * challenge is decided by time or elimination rather than by someone
 * crossing a target. Same types (and so the same celebration screens) as
 * a race finish; metadata.decidedAtEnd tells the two apart.
 * @param {string} competitionTitle The challenge's title.
 * @param {OutcomeParticipant[]} participants Everyone in the challenge.
 * @param {Array<{uid: string, position: number}>} placements Who placed
 *   where; position 1 is a win.
 * @return {EventDraft[]} The placement event drafts to persist.
 */
export function detectPlacementEvents(
  competitionTitle: string,
  participants: OutcomeParticipant[],
  placements: {uid: string; position: number}[]
): EventDraft[] {
  const sharedWin = placements.filter((p) => p.position === 1).length > 1;

  return placements.map((placement) => {
    const actor = participants.find((p) => p.uid === placement.uid);
    return {
      type: placement.position === 1 ? "won" : "finishedInPosition",
      recipients: othersThan(participants, placement.uid),
      target: {kind: "create"},
      payload: {
        competitionTitle,
        actorUid: placement.uid,
        actorUsername: actor?.username ?? "Someone",
        targetUid: null,
        targetUsername: null,
        metadata: {
          position: placement.position,
          decidedAtEnd: true,
          ...(placement.position === 1 && sharedWin ? {sharedWin: true} : {}),
        },
      },
    };
  });
}
