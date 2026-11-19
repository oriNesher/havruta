import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {parseChallenge} from "../challenges/model";
import {
  joinClosedReason,
  joinRefusedReason,
  personalGoalFields,
  sharedGoalFields,
} from "../challenges/joining";
import {writeParticipantJoin} from "../challenges/addParticipant";

interface AcceptInviteRequest {
  inviteId: string;
  /** Legacy Personal Goal challenges only: the joiner's own goal. */
  goalTitle?: string;
  targetValue?: number;
}

/**
 * Accepts a direct (username/email) invite. Runs server-side for the same
 * reason redeemInvite does: firestore.rules no longer lets a client add
 * itself to a challenge, so being invited is checked here — the invite
 * must exist, be addressed to the caller, and still be pending — and the
 * join, the participant doc and the invite's status land in one
 * transaction.
 */
export const acceptInvite = onCall<AcceptInviteRequest>(
  {maxInstances: 5},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in to join.");
    }

    const inviteId = request.data?.inviteId;
    if (!inviteId || typeof inviteId !== "string") {
      throw new HttpsError("invalid-argument", "inviteId is required.");
    }

    const db = admin.firestore();
    const inviteRef = db.collection("competition_invites").doc(inviteId);

    const result = await db.runTransaction(async (tx) => {
      const inviteSnap = await tx.get(inviteRef);
      if (!inviteSnap.exists) {
        throw new HttpsError("not-found", "This invite no longer exists.");
      }

      const invite = inviteSnap.data() ?? {};
      if (invite.toUid !== uid) {
        throw new HttpsError("permission-denied", "This invite isn't yours.");
      }
      if (invite.status !== "pending") {
        throw new HttpsError(
          "failed-precondition",
          "This invite was already answered."
        );
      }

      const competitionId = invite.competitionId;
      if (typeof competitionId !== "string" || !competitionId) {
        throw new HttpsError("not-found", "This challenge no longer exists.");
      }

      const competitionRef = db.collection("competitions").doc(competitionId);
      const [competitionSnap, participantSnap, userSnap] = await Promise.all([
        tx.get(competitionRef),
        tx.get(competitionRef.collection("participants").doc(uid)),
        tx.get(db.collection("users").doc(uid)),
      ]);

      if (!competitionSnap.exists) {
        throw new HttpsError("not-found", "This challenge no longer exists.");
      }

      const acceptedFields = {
        status: "accepted",
        acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Idempotent: already in (an invite link, a retried call) just
      // settles the invite.
      if (participantSnap.exists) {
        tx.update(inviteRef, acceptedFields);
        return {competitionId, alreadyJoined: true};
      }

      const challenge = parseChallenge(competitionSnap.data() ?? {});
      const closedReason = joinClosedReason(challenge, Date.now()) ??
        joinRefusedReason(challenge, uid);
      if (closedReason) {
        throw new HttpsError("failed-precondition", closedReason);
      }

      const goalFields = challenge.isLegacyPersonal ?
        personalGoalFields(request.data) :
        sharedGoalFields(challenge);
      if (!goalFields) {
        throw new HttpsError(
          "invalid-argument",
          "This is a personal goal challenge — goalTitle and targetValue " +
            "are required to join."
        );
      }

      const username = userSnap.data()?.username ?? "Someone";
      writeParticipantJoin(tx, competitionRef, uid, username, goalFields);
      tx.update(inviteRef, acceptedFields);

      return {competitionId, alreadyJoined: false};
    });

    logger.info("Direct invite accepted", {inviteId, uid, result});

    return result;
  }
);
