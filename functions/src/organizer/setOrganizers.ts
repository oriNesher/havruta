import {onCall} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {asCallable, loadAsOrganizer, requireCaller, writeAudit} from "./access";
import {OrganizerError} from "./errors";
import {planOrganizerChange} from "./organizers";

interface SetOrganizersRequest {
  competitionId: string;
  /** A uid to make co-organizer (found via publicProfiles). */
  add?: string;
  /** A uid to stop being an organizer (may be the caller). */
  remove?: string;
}

/**
 * Adds or removes one co-organizer. Organizers don't have to compete:
 * being on organizerUids alone gives read access to the challenge and its
 * organizer data (firestore.rules) and the organizer callables.
 */
export const setOrganizers = onCall<SetOrganizersRequest>(
  {maxInstances: 5},
  (request) => asCallable(async () => {
    const {uid, competitionId} = requireCaller(request);
    const db = admin.firestore();

    const organizerUids = await db.runTransaction(async (tx) => {
      const ctx = await loadAsOrganizer(tx, competitionId, uid);
      const targetUid = (request.data?.add ?? request.data?.remove) as unknown;
      const targetSnap = typeof targetUid === "string" && targetUid ?
        await tx.get(db.collection("users").doc(targetUid)) :
        null;

      const next = planOrganizerChange(ctx.challenge.organizerUids, {
        add: request.data?.add,
        remove: request.data?.remove,
      });
      const adding = next.length > ctx.challenge.organizerUids.length;
      if (adding && !targetSnap?.exists) {
        throw new OrganizerError("That user doesn't exist.");
      }

      tx.update(ctx.ref, {organizerUids: next});
      writeAudit(tx, ctx, {
        action: adding ? "addOrganizer" : "removeOrganizer",
        targetUid: targetUid as string,
        targetUsername: targetSnap?.data()?.username ?? null,
        before: {organizerUids: ctx.challenge.organizerUids},
        after: {organizerUids: next},
      });
      return next;
    });

    logger.info("Organizers changed", {competitionId, uid, organizerUids});
    return {organizerUids};
  })
);
