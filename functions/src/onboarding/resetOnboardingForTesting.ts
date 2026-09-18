// TEMPORARY — onboarding test harness only (see the Part 2 section of
// lib/debug/onboarding_debug_screen.dart). Delete this file, its export in
// index.ts, and its client wrapper once the onboarding flow is verified.
//
// It exists because the tutorial can't be replayed from the client alone:
// firestore.rules deliberately won't let a user un-accept an invitation or
// remove themselves from a challenge's participantUids, so re-running
// Module 1 needs the onboarding records deleted and recreated server-side.

import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {
  ONBOARDING_CHALLENGES,
  onboardingCompetitionId,
  onboardingInviteId,
} from "./config";

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
 * TEMPORARY: deletes the calling user's onboarding challenges (with their
 * participants/events subcollections), onboarding invitations, and
 * onboarding_state ledger, so a later startOnboarding call recreates them
 * fresh with pending invitations. Only ever touches the caller's own
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

    return {deleted};
  }
);
