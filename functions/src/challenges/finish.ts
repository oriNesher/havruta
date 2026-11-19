import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {EventDraft, EventsContext} from "../events/types";
import {parseChallenge} from "./model";
import {claimFinish} from "./winConditions/firstToTarget";
import {COMPLETION_TYPES} from "../events/corrections";

/**
 * Settles a race completion the progression rule detected: claims the
 * actor's finish position in a transaction on the competition doc (which
 * also records the winner, and completes the challenge once everyone has
 * finished), then rewrites the completion draft to match. The rule's own
 * position comes from a non-transactional count, so the transaction's
 * answer always wins.
 * @param {EventsContext} context Shared context for this participant update.
 * @param {EventDraft[]} drafts Every draft from this trigger invocation.
 * @return {Promise<EventDraft[]>} The drafts to persist — the completion
 *   draft corrected, or dropped if this finish was already claimed by an
 *   earlier delivery of the same trigger.
 */
export async function settleRaceFinish(
  context: EventsContext,
  drafts: EventDraft[]
): Promise<EventDraft[]> {
  const completion = drafts.find((d) => COMPLETION_TYPES.includes(d.type));
  if (!completion) return drafts;

  const db = admin.firestore();
  const competitionRef = db.collection("competitions")
    .doc(context.competitionId);

  const claim = await db.runTransaction(async (tx) => {
    const snap = await tx.get(competitionRef);
    const data = snap.data() ?? {};
    const participantUids = Array.isArray(data.participantUids) ?
      data.participantUids as string[] :
      context.participantUids;

    const result = claimFinish(
      parseChallenge(data),
      context.actorUid,
      participantUids,
      context.completionsCount
    );

    if (result.update) {
      tx.update(competitionRef, {
        ...result.update,
        ...(result.completes ?
          {completedAt: admin.firestore.FieldValue.serverTimestamp()} :
          {}),
      });
    }

    return result;
  });

  logger.info("Race finish settled", {
    competitionId: context.competitionId,
    actorUid: context.actorUid,
    position: claim.position,
    alreadyClaimed: claim.alreadyClaimed,
    completes: claim.completes,
  });

  if (claim.alreadyClaimed) {
    return drafts.filter((d) => d !== completion);
  }

  const settled: EventDraft = {
    ...completion,
    type: claim.position === 1 ? "won" : "finishedInPosition",
    payload: {
      ...completion.payload,
      metadata: {
        ...(completion.payload.metadata as Record<string, unknown>),
        position: claim.position,
      },
    },
  };

  return drafts.map((d) => d === completion ? settled : d);
}
