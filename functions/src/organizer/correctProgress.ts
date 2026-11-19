import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {toStandingParticipant} from "../challenges/standings";
import {asCallable, loadAsOrganizer, requireCaller, writeAudit} from "./access";
import {planCorrection, requireReason} from "./correction";
import {OrganizerError} from "./errors";

interface CorrectProgressRequest {
  competitionId: string;
  uid: string;
  /** The participant's corrected total. */
  progress: number;
  /** Challenge day (YYYY-MM-DD) the difference lands on; default today. */
  dayKey?: string;
  reason: string;
}

/**
 * Organizer correction of a participant's progress, with an audit record
 * (who, when, old value, new value, reason). One transaction writes:
 * - an entries/{id} doc (source organizerCorrection) — the same entries
 *   collection proof-backed entries will use, so a correction is one more
 *   entry in the participant's history;
 * - the participant's new total and that day's ledger bucket, plus
 *   lastCorrectionId, which tells the progress triggers this write was a
 *   correction: it settles a race finish and the Aggressor Badge, but
 *   fires no celebrations, social events, streak or push;
 * - the audit record.
 */
export const correctProgress = onCall<CorrectProgressRequest>(
  {maxInstances: 5},
  (request) => asCallable(async () => {
    const {uid, competitionId} = requireCaller(request);
    const targetUid = request.data?.uid;
    if (typeof targetUid !== "string" || !targetUid) {
      throw new HttpsError("invalid-argument", "uid is required.");
    }
    const reason = requireReason(request.data?.reason);

    const result = await admin.firestore().runTransaction(async (tx) => {
      const ctx = await loadAsOrganizer(tx, competitionId, uid);
      const participantRef = ctx.ref.collection("participants").doc(targetUid);
      const participantSnap = await tx.get(participantRef);
      if (!participantSnap.exists) {
        throw new OrganizerError("They aren't in this challenge.");
      }

      const participant =
        toStandingParticipant(participantSnap.data() ?? {}, ctx.challenge);
      const plan = planCorrection(
        ctx.challenge,
        participant,
        request.data?.progress,
        request.data?.dayKey,
        Date.now()
      );

      const entryRef = ctx.ref.collection("entries").doc();
      tx.set(entryRef, {
        uid: targetUid,
        amount: plan.delta,
        dayKey: plan.dayKey,
        source: {type: "organizerCorrection"},
        status: "counted",
        verified: true,
        correction: {
          from: plan.from,
          to: plan.to,
          byUid: ctx.actorUid,
          byUsername: ctx.actorUsername,
          reason,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      tx.update(
        participantRef,
        "progress", plan.to,
        new admin.firestore.FieldPath("dailyProgress", plan.dayKey),
        plan.dayAmount,
        "updatedAt", admin.firestore.FieldValue.serverTimestamp(),
        "lastCorrectionId", entryRef.id
      );

      writeAudit(tx, ctx, {
        action: "correctProgress",
        targetUid,
        targetUsername: participant.username,
        before: {progress: plan.from},
        after: {progress: plan.to, dayKey: plan.dayKey},
        reason,
        entryId: entryRef.id,
      });

      return {entryId: entryRef.id, from: plan.from, to: plan.to};
    });

    logger.info("Progress corrected", {competitionId, uid, targetUid, result});
    return result;
  })
);
