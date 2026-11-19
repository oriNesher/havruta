import {EventDraft} from "../types";
import {Audience, audienceFor} from "../audience";

/** The participant fields outcome events need. */
export interface OutcomeParticipant {
  uid: string;
  username: string;
}

/** Placements announced to everyone in a large challenge. */
const PODIUM = 3;

/**
 * Recipients of an outcome event: everyone but the actor in a small
 * challenge; the given reach of the audience in a large one.
 * @param {OutcomeParticipant[]} participants Everyone in the challenge.
 * @param {string} actorUid The event's actor.
 * @param {Audience | null | undefined} audience Large-challenge audience.
 * @param {string} tier How widely it travels: everyone, nearby or social.
 * @return {string[]} The event's recipients.
 */
function recipients(
  participants: OutcomeParticipant[],
  actorUid: string,
  audience: Audience | null | undefined,
  tier: "everyone" | "nearby" | "social"
): string[] {
  return audienceFor(audience, participants.map((p) => p.uid), actorUid,
    tier);
}

/**
 * Creates an "eliminated" event per participant knocked out of a Last One
 * Standing challenge, sent to everyone else. Not celebration-eligible:
 * it's news for the others, not a moment for the person who's out.
 * @param {string} competitionTitle The challenge's title.
 * @param {OutcomeParticipant[]} participants Everyone in the challenge.
 * @param {Array<{uid: string, day: string, dayNumber: number}>}
 *   eliminations Who went out, and on which day.
 * @param {Audience | null} [audience] A large challenge's audience: then
 *   an elimination reaches the people near them, not everyone.
 * @return {EventDraft[]} The eliminated event drafts to persist.
 */
export function detectEliminationEvents(
  competitionTitle: string,
  participants: OutcomeParticipant[],
  eliminations: {uid: string; day: string; dayNumber: number}[],
  audience?: Audience | null
): EventDraft[] {
  return eliminations.map((elimination) => {
    const actor = participants.find((p) => p.uid === elimination.uid);
    return {
      type: "eliminated",
      recipients: recipients(participants, elimination.uid, audience,
        "nearby"),
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
 * @param {Audience | null} [audience] A large challenge's audience: then
 *   only the podium is announced to everyone; the rest of the placings
 *   reach followers and teammates (each person still gets their own).
 * @return {EventDraft[]} The placement event drafts to persist.
 */
export function detectPlacementEvents(
  competitionTitle: string,
  participants: OutcomeParticipant[],
  placements: {uid: string; position: number}[],
  audience?: Audience | null
): EventDraft[] {
  const sharedWin = placements.filter((p) => p.position === 1).length > 1;

  return placements.map((placement) => {
    const actor = participants.find((p) => p.uid === placement.uid);
    return {
      type: placement.position === 1 ? "won" : "finishedInPosition",
      recipients: recipients(participants, placement.uid, audience,
        placement.position <= PODIUM ? "everyone" : "social"),
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
