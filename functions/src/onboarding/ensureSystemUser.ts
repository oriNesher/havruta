import {FieldValue} from "firebase-admin/firestore";
import {SYSTEM_USER_UID, SYSTEM_USERNAME} from "./config";

/**
 * Idempotently ensures the users/{SYSTEM_USER_UID} doc exists, so the
 * system user has a normal-looking profile (username, usernameLower) that
 * existing client code can read the same way it reads any other user's —
 * e.g. HomePendingInvitesSection's "Invited by: Havruta" via
 * getUsernameByUid. Check-then-create rather than a blind merge-write, so
 * repeated onboarding runs don't keep resetting createdAt.
 * @param {FirebaseFirestore.Firestore} db The Firestore instance.
 * @return {Promise<void>} Resolves once the doc is known to exist.
 */
export async function ensureSystemUserDoc(
  db: FirebaseFirestore.Firestore
): Promise<void> {
  const ref = db.collection("users").doc(SYSTEM_USER_UID);
  const snap = await ref.get();
  if (snap.exists) {
    return;
  }

  // A concurrent onboarding run could race here and also see !exists; both
  // writes carry identical content, so the harmless outcome is last-write-
  // wins on the same data rather than a transaction.
  await ref.set({
    uid: SYSTEM_USER_UID,
    username: SYSTEM_USERNAME,
    usernameLower: SYSTEM_USERNAME.toLowerCase(),
    email: null,
    isSystemUser: true,
    createdAt: FieldValue.serverTimestamp(),
  });
}
