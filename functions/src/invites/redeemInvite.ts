import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

interface RedeemInviteRequest {
  linkId: string;
  goalTitle?: string;
  targetValue?: number;
  unit?: string;
}

// Redemption must run server-side, inside a transaction: the client only
// holds a bearer token (the link id), and a plain client-side write would
// let anyone with the link grant themselves participant access regardless
// of capacity/expiry/revocation — see the invite-flow redesign plan.
export const redeemInvite = onCall<RedeemInviteRequest>(
  {maxInstances: 5},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in to join.");
    }

    const linkId = request.data?.linkId;
    if (!linkId || typeof linkId !== "string") {
      throw new HttpsError("invalid-argument", "linkId is required.");
    }

    const db = admin.firestore();
    const linkRef = db.collection("challenge_invite_links").doc(linkId);

    const result = await db.runTransaction(async (tx) => {
      const linkSnap = await tx.get(linkRef);
      if (!linkSnap.exists) {
        throw new HttpsError("not-found", "This invite link doesn't exist.");
      }

      const linkData = linkSnap.data() || {};
      if (linkData.revoked === true) {
        throw new HttpsError(
          "failed-precondition",
          "This invite link has been revoked."
        );
      }

      const expiresAt = linkData.expiresAt as
        | admin.firestore.Timestamp
        | undefined;
      if (expiresAt && expiresAt.toMillis() < Date.now()) {
        throw new HttpsError(
          "failed-precondition",
          "This invite link has expired."
        );
      }

      const maxRedemptions = linkData.maxRedemptions as number | null;
      const redemptionCount = (linkData.redemptionCount as number) ?? 0;
      if (
        typeof maxRedemptions === "number" &&
        redemptionCount >= maxRedemptions
      ) {
        throw new HttpsError(
          "failed-precondition",
          "This invite link has reached its limit."
        );
      }

      const competitionId = linkData.competitionId as string;
      const competitionRef = db.collection("competitions").doc(competitionId);
      const competitionSnap = await tx.get(competitionRef);

      if (!competitionSnap.exists) {
        throw new HttpsError("not-found", "This challenge no longer exists.");
      }

      const competitionData = competitionSnap.data() || {};
      if (competitionData.status !== "active") {
        throw new HttpsError(
          "failed-precondition",
          "This challenge is no longer active."
        );
      }

      const participantRef = competitionRef
        .collection("participants")
        .doc(uid);
      const redemptionRef = linkRef.collection("redemptions").doc(uid);

      const [participantSnap, redemptionSnap] = await Promise.all([
        tx.get(participantRef),
        tx.get(redemptionRef),
      ]);

      // Idempotent: double-tap, retry-after-timeout, or the creator opening
      // their own link (already a participant since creation) all resolve
      // as a harmless no-op rather than an error.
      if (participantSnap.exists || redemptionSnap.exists) {
        return {competitionId, alreadyJoined: true};
      }

      const userSnap = await tx.get(db.collection("users").doc(uid));
      const username = userSnap.data()?.username ?? "Someone";

      const competitionType = competitionData.type as string;
      let goalTitle: string;
      let targetValue: number;
      let unit: string;

      if (competitionType === "sharedGoalChallenge") {
        goalTitle = competitionData.sharedGoalTitle ?? "";
        targetValue = competitionData.sharedTargetValue ?? 0;
        unit = competitionData.sharedUnit ?? "";
      } else {
        const {goalTitle: g, targetValue: t, unit: u} = request.data;
        if (!g || !t || t <= 0 || !u) {
          throw new HttpsError(
            "invalid-argument",
            "This is a personal goal challenge — goalTitle, targetValue, " +
              "and unit are required to join."
          );
        }
        goalTitle = g;
        targetValue = t;
        unit = u;
      }

      tx.update(competitionRef, {
        participantUids: admin.firestore.FieldValue.arrayUnion(uid),
      });

      tx.set(participantRef, {
        uid,
        username,
        goalTitle,
        targetValue,
        unit,
        progress: 0,
        joinedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      tx.set(redemptionRef, {
        uid,
        username,
        redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(competitionType !== "sharedGoalChallenge" ?
          {goalTitle, targetValue, unit} :
          {}),
      });

      tx.update(linkRef, {
        redemptionCount: admin.firestore.FieldValue.increment(1),
      });

      return {competitionId, alreadyJoined: false};
    });

    logger.info("Invite redeemed", {linkId, uid, result});

    return result;
  }
);
