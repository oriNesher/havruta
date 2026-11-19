import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

interface FindUserByEmailRequest {
  email: string;
}

/**
 * Invite-by-email lookup. Emails live only on the owner-readable users
 * doc, so the lookup runs server-side: exact match only (no prefix search
 * to enumerate addresses with), and it returns just what the invite needs
 * — never the email or anything else from the users doc.
 */
export const findUserByEmail = onCall<FindUserByEmailRequest>(
  {maxInstances: 5},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const raw = request.data?.email;
    const email = typeof raw === "string" ? raw.trim().toLowerCase() : "";
    if (!email.includes("@") || email.length > 320) {
      throw new HttpsError("invalid-argument", "A valid email is required.");
    }

    const snap = await admin.firestore()
      .collection("users")
      .where("emailLower", "==", email)
      .limit(1)
      .get();

    const doc = snap.docs[0];
    const username = doc?.data().username;
    if (!doc || typeof username !== "string" || !username) {
      return {user: null};
    }
    return {user: {uid: doc.id, username}};
  }
);
