import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

interface RevokeInviteRequest {
  linkId: string;
}

export const revokeInvite = onCall<RevokeInviteRequest>(
  {maxInstances: 5},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const linkId = request.data?.linkId;
    if (!linkId || typeof linkId !== "string") {
      throw new HttpsError("invalid-argument", "linkId is required.");
    }

    const db = admin.firestore();
    const linkRef = db.collection("challenge_invite_links").doc(linkId);
    const linkSnap = await linkRef.get();

    if (!linkSnap.exists) {
      throw new HttpsError("not-found", "This invite link doesn't exist.");
    }

    if (linkSnap.data()?.createdBy !== uid) {
      throw new HttpsError(
        "permission-denied",
        "Only the creator of this invite link can revoke it."
      );
    }

    await linkRef.update({
      revoked: true,
      revokedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {revoked: true};
  }
);
