// TEMPORARY — onboarding test harness only (see the Part 2 section of
// lib/debug/onboarding_debug_screen.dart). Delete this file, its export in
// index.ts, and its client wrapper once the onboarding flow is verified.
//
// It exists because the tutorial can't be replayed from the client alone:
// firestore.rules deliberately won't let a user un-accept an invitation or
// remove themselves from a challenge's participantUids, so re-running
// Module 1 needs the onboarding records deleted and recreated server-side.
// Likewise only Cloud Functions may delete events, so replaying the Part 3
// win (Module 2/3) needs Challenge A's events cleared server-side too — the
// "acceptInvitesProgress" scope below.

import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {
  ONBOARDING_CHALLENGES,
  onboardingCompetitionId,
  onboardingInviteId,
} from "./config";

/** What a reset call wipes. */
type ResetScope = "all" | "acceptInvitesProgress";

/**
 * Whether a document's onboarding metadata marks it as this user's own
 * onboarding record. Guards every delete below, so a mistyped or reused
 * document id can never take out real user data.
 * @param {FirebaseFirestore.DocumentData | undefined} data Document data.
 * @param {string} uid The calling user's uid.
 * @return {boolean} True if the doc is that user's onboarding record.
 */
function isOnboardingRecordFor(
  data: FirebaseFirestore.DocumentData | undefined,
  uid: string
): boolean {
  const meta = data?.onboarding;
  return meta?.isOnboarding === true && meta?.onboardingUserId === uid;
}

/**
 * Rewinds the caller's Challenge A ("acceptInvites") to the state right
 * after both invitations were accepted: their participant progress back to
 * 0 and every event/progress cursor in the challenge deleted, so the next
 * progress report is again a first-place "won" with a fresh celebration.
 * Membership, invites, the system user's participant doc and Challenge B
 * are left untouched.
 * @param {FirebaseFirestore.Firestore} db The Firestore instance.
 * @param {string} uid The calling user's uid.
 * @return {Promise<string[]>} The paths that were reset or deleted.
 */
async function resetAcceptInvitesProgress(
  db: FirebaseFirestore.Firestore,
  uid: string
): Promise<string[]> {
  const competitionRef = db
    .collection("competitions")
    .doc(onboardingCompetitionId(uid, "acceptInvites"));
  const competitionSnap = await competitionRef.get();
  if (!competitionSnap.exists) {
    throw new HttpsError("not-found", `${competitionRef.path} does not exist`);
  }
  if (!isOnboardingRecordFor(competitionSnap.data(), uid) ||
    competitionSnap.data()?.onboarding?.onboardingChallengeKey !==
      "acceptInvites") {
    throw new HttpsError(
      "failed-precondition",
      `${competitionRef.path} is not this user's Challenge A`
    );
  }

  const participantRef = competitionRef.collection("participants").doc(uid);
  if (!(await participantRef.get()).exists) {
    throw new HttpsError(
      "failed-precondition",
      "Not a participant of Challenge A — accept its invitation first"
    );
  }

  const touched: string[] = [];
  // Events first, so nothing can observe "progress 0" next to a stale win.
  // Lowering progress fires the participant triggers, which both skip
  // decreases, so this writes no new events of its own.
  for (const sub of ["events", "progressCursors"]) {
    const ref = competitionRef.collection(sub);
    await db.recursiveDelete(ref);
    touched.push(ref.path);
  }
  await participantRef.update({
    progress: 0,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  touched.push(`${participantRef.path} (progress -> 0)`);
  return touched;
}

/**
 * TEMPORARY: with the default scope ("all"), deletes the calling user's
 * onboarding challenges (with their participants/events subcollections),
 * onboarding invitations, and onboarding_state ledger, so a later
 * startOnboarding call recreates them fresh with pending invitations. With
 * scope "acceptInvitesProgress", only rewinds Challenge A's progress (see
 * resetAcceptInvitesProgress). Only ever touches the caller's own
 * deterministic onboarding document ids, and only after verifying their
 * onboarding metadata.
 */
export const resetOnboardingForTesting = onCall(
  {maxInstances: 2},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const db = admin.firestore();
    const scope: ResetScope =
      request.data?.scope === "acceptInvitesProgress" ?
        "acceptInvitesProgress" :
        "all";

    if (scope === "acceptInvitesProgress") {
      const reset = await resetAcceptInvitesProgress(db, uid);
      logger.info("Onboarding Challenge A progress reset for testing", {
        uid,
        reset,
      });
      return {scope, deleted: reset};
    }

    const deleted: string[] = [];

    for (const config of ONBOARDING_CHALLENGES) {
      const competitionRef = db
        .collection("competitions")
        .doc(onboardingCompetitionId(uid, config.key));
      const competitionSnap = await competitionRef.get();

      if (competitionSnap.exists) {
        if (!isOnboardingRecordFor(competitionSnap.data(), uid)) {
          throw new HttpsError(
            "failed-precondition",
            `${competitionRef.path} is not this user's onboarding challenge`
          );
        }
        // Parent doc first, then descendants — the same order the client's
        // deleteCompetition uses, so onParticipantLeaveCreateEvents sees the
        // challenge already gone and skips writing a bogus "left" event.
        await competitionRef.delete();
        await db.recursiveDelete(competitionRef);
        deleted.push(competitionRef.path);
      }

      const inviteRef = db
        .collection("competition_invites")
        .doc(onboardingInviteId(uid, config.key));
      const inviteSnap = await inviteRef.get();

      if (inviteSnap.exists) {
        if (!isOnboardingRecordFor(inviteSnap.data(), uid)) {
          throw new HttpsError(
            "failed-precondition",
            `${inviteRef.path} is not this user's onboarding invite`
          );
        }
        await inviteRef.delete();
        deleted.push(inviteRef.path);
      }
    }

    const ledgerRef = db.collection("onboarding_state").doc(uid);
    if ((await ledgerRef.get()).exists) {
      await ledgerRef.delete();
      deleted.push(ledgerRef.path);
    }

    logger.info("Onboarding reset for testing", {uid, deleted});

    return {scope, deleted};
  }
);
