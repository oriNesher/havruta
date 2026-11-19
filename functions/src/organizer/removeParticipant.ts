import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {asCallable, loadAsOrganizer, requireCaller, writeAudit} from "./access";
import {MAX_REASON} from "./correction";
import {OrganizerError} from "./errors";
import {raceCompletesOnRemoval} from "./removal";

interface RemoveParticipantRequest {
  competitionId: string;
  uid: string;
  reason?: string;
}

/**
 * Organizer removes a participant from a running challenge: their
 * participant doc goes, they leave participantUids, and they're recorded
 * on removedUids so no invite (link or direct) can bring them back. The
 * existing participant-deleted trigger then posts the usual "left" event
 * and passes on the Aggressor Badge if they held it. Their correction
 * entries stay, as part of the audit trail.
 */
export const removeParticipant = onCall<RemoveParticipantRequest>(
  {maxInstances: 5},
  (request) => asCallable(async () => {
    const {uid, competitionId} = requireCaller(request);
    const targetUid = request.data?.uid;
    if (typeof targetUid !== "string" || !targetUid) {
      throw new HttpsError("invalid-argument", "uid is required.");
    }
    const rawReason = request.data?.reason;
    const reason = typeof rawReason === "string" ? rawReason.trim() : "";
    if (reason.length > MAX_REASON) {
      throw new OrganizerError(
        `The reason can be at most ${MAX_REASON} characters.`);
    }

    await admin.firestore().runTransaction(async (tx) => {
      const ctx = await loadAsOrganizer(tx, competitionId, uid);
      const participantRef = ctx.ref.collection("participants").doc(targetUid);
      const participantSnap = await tx.get(participantRef);

      if (ctx.challenge.status !== "active") {
        throw new OrganizerError(
          "This challenge is over; its participants are final.");
      }
      if (!participantSnap.exists &&
        !ctx.challenge.participantUids.includes(targetUid)) {
        throw new OrganizerError("They aren't in this challenge.");
      }

      const participant = participantSnap.data() ?? {};
      tx.delete(participantRef);
      tx.update(ctx.ref, {
        participantUids: admin.firestore.FieldValue.arrayRemove(targetUid),
        removedUids: admin.firestore.FieldValue.arrayUnion(targetUid),
        ...(raceCompletesOnRemoval(ctx.challenge, targetUid) ? {
          status: "completed",
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        } : {}),
      });
      writeAudit(tx, ctx, {
        action: "removeParticipant",
        targetUid,
        targetUsername: participant.username ?? null,
        before: {progress: participant.progress ?? 0},
        reason: reason || null,
      });
    });

    logger.info("Participant removed", {competitionId, uid, targetUid});
    return {removed: true};
  })
);
