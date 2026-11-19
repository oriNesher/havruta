import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {publicProfileFor} from "./publicProfile";

/**
 * Keeps publicProfiles/{uid} in step with users/{uid}. Writes on every
 * users-doc change rather than only when the username changes, so any
 * profile missed by the backfill heals the next time its owner opens the
 * app (which always writes the users doc: streak, push token).
 */
export const syncPublicProfile = onDocumentWritten(
  {document: "users/{uid}", maxInstances: 5},
  async (event) => {
    const uid = event.params.uid;
    const ref = admin.firestore().collection("publicProfiles").doc(uid);
    const profile = publicProfileFor(uid, event.data?.after.data());

    if (!profile) {
      await ref.delete();
      return;
    }
    await ref.set(profile);
  }
);
