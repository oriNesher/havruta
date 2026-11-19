import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {toStandingParticipant} from "../challenges/standings";
import {asCallable, loadAsOrganizer, requireCaller, writeAudit} from "./access";
import {requireReason} from "./correction";
import {OrganizerError} from "./errors";
import {planReinstatement} from "./reinstate";

interface ReinstateParticipantRequest {
  competitionId: string;
  uid: string;
  reason: string;
}

/**
 * Organizer overrules a Last One Standing elimination (see
 * planReinstatement): clears the participant's eliminatedOnDay /
 * eliminatedAt so they can log again and are judged from the next
 * unjudged day. Requires a reason; audited with the overruled day.
 */
export const reinstateParticipant = onCall<ReinstateParticipantRequest>(
  {maxInstances: 5},
  (request) => asCallable(async () => {
    const {uid, competitionId} = requireCaller(request);
    const targetUid = request.data?.uid;
    if (typeof targetUid !== "string" || !targetUid) {
      throw new HttpsError("invalid-argument", "uid is required.");
    }
    const reason = requireReason(request.data?.reason);

    const day = await admin.firestore().runTransaction(async (tx) => {
      const ctx = await loadAsOrganizer(tx, competitionId, uid);
      const participantRef = ctx.ref.collection("participants").doc(targetUid);
      const participantSnap = await tx.get(participantRef);
      if (!participantSnap.exists) {
        throw new OrganizerError("They aren't in this challenge.");
      }

      const participant =
        toStandingParticipant(participantSnap.data() ?? {}, ctx.challenge);
      const {day} = planReinstatement(ctx.challenge, participant);

      tx.update(participantRef, {
        eliminatedOnDay: admin.firestore.FieldValue.delete(),
        eliminatedAt: admin.firestore.FieldValue.delete(),
      });
      writeAudit(tx, ctx, {
        action: "reinstateParticipant",
        targetUid,
        targetUsername: participant.username,
        before: {eliminatedOnDay: day},
        after: {eliminatedOnDay: null},
        reason,
      });
      return day;
    });

    logger.info("Participant reinstated", {competitionId, uid, targetUid, day});
    return {reinstated: true, overruledDay: day};
  })
);
