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
// "acceptInvitesProgress" scope below — and replaying Part 4 (Module 4)
// needs Havruta's scripted progress in Challenge B rewound — the
// "eventsRespectProgress" scope.
//
// No scope ever clears the onboarding Respect grant marker
// (onboarding_state/{uid}.respectGrant): this callable is reachable by any
// signed-in user while it's deployed, and clearing it would make the grant
// farmable.

import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {FieldValue} from "firebase-admin/firestore";
import {
  ONBOARDING_CHALLENGES,
  SYSTEM_USER_UID,
  onboardingCompetitionId,
  onboardingInviteId,
} from "./config";

/** What a reset call wipes. */
type ResetScope = "all" | "acceptInvitesProgress" | "eventsRespectProgress";

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
 * Rewinds the caller's Challenge B ("challengeFriends") to the state right
 * before Module 4 ran: Havruta's participant progress back to 0, every
 * event Havruta is the actor of (and its progress cursor) deleted, and the
 * ledger's eventsRespect marker cleared, so ensureOnboardingSystemProgress
 * applies the scripted progress again and the pipeline writes a fresh
 * Event. The caller's own membership, events and Respect grant marker are
 * left alone.
 *
 * Each deleted event also has any Respect the caller gave it reversed, in
 * the same transaction as the delete — so a replay doesn't cost the tester
 * a Respect, and a retried reset can't refund twice (the event is already
 * gone the second time).
 * @param {FirebaseFirestore.Firestore} db The Firestore instance.
 * @param {string} uid The calling user's uid.
 * @return {Promise<string[]>} The paths that were reset or deleted.
 */
async function resetEventsRespectProgress(
  db: FirebaseFirestore.Firestore,
  uid: string
): Promise<string[]> {
  const competitionRef = db
    .collection("competitions")
    .doc(onboardingCompetitionId(uid, "challengeFriends"));
  const competitionSnap = await competitionRef.get();
  if (!competitionSnap.exists) {
    throw new HttpsError("not-found", `${competitionRef.path} does not exist`);
  }
  if (!isOnboardingRecordFor(competitionSnap.data(), uid) ||
    competitionSnap.data()?.onboarding?.onboardingChallengeKey !==
      "challengeFriends") {
    throw new HttpsError(
      "failed-precondition",
      `${competitionRef.path} is not this user's Challenge B`
    );
  }
  const systemParticipantRef = competitionRef
    .collection("participants")
    .doc(SYSTEM_USER_UID);
  const systemParticipant = await systemParticipantRef.get();
  if (systemParticipant.data()?.uid !== SYSTEM_USER_UID) {
    throw new HttpsError(
      "failed-precondition",
      "Challenge B has no system participant"
    );
  }

  const touched: string[] = [];
  const userRef = db.collection("users").doc(uid);
  const systemUserRef = db.collection("users").doc(SYSTEM_USER_UID);
  const systemEvents = await competitionRef
    .collection("events")
    .where("actorUid", "==", SYSTEM_USER_UID)
    .get();
  for (const doc of systemEvents.docs) {
    const refunded = await db.runTransaction(async (tx) => {
      const snap = await tx.get(doc.ref);
      if (!snap.exists) return false;
      const givenBy = (snap.data()?.respectGivenBy as string[]) ?? [];
      const refund = givenBy.includes(uid);
      if (refund) {
        tx.update(userRef, {respectBalance: FieldValue.increment(1)});
        tx.update(systemUserRef, {
          totalRespectReceived: FieldValue.increment(-1),
        });
      }
      tx.delete(doc.ref);
      return refund;
    });
    touched.push(`${doc.ref.path}${refunded ? " (Respect refunded)" : ""}`);
  }

  const cursorRef = competitionRef
    .collection("progressCursors")
    .doc(SYSTEM_USER_UID);
  await cursorRef.delete();
  touched.push(cursorRef.path);

  // Lowering progress fires the participant triggers, which both skip
  // decreases, so this writes no new events of its own. The streak fields
  // claimActiveDay wrote go too, so the replay looks like a first update.
  await systemParticipantRef.update({
    progress: 0,
    currentStreak: FieldValue.delete(),
    lastActiveDate: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  touched.push(`${systemParticipantRef.path} (progress -> 0)`);

  const ledgerRef = db.collection("onboarding_state").doc(uid);
  if ((await ledgerRef.get()).exists) {
    await ledgerRef.update({eventsRespect: FieldValue.delete()});
    touched.push(`${ledgerRef.path}.eventsRespect`);
  }
  return touched;
}

/**
 * TEMPORARY: with the default scope ("all"), deletes the calling user's
 * onboarding challenges (with their participants/events subcollections),
 * onboarding invitations, and onboarding_state ledger, so a later
 * startOnboarding call recreates them fresh with pending invitations. With
 * scope "acceptInvitesProgress", only rewinds Challenge A's progress (see
 * resetAcceptInvitesProgress), and with scope "eventsRespectProgress" only
 * rewinds Havruta's Module 4 progress in Challenge B (see
 * resetEventsRespectProgress). Only ever touches the caller's own
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
    const requested = request.data?.scope;
    const scope: ResetScope =
      requested === "acceptInvitesProgress" ||
      requested === "eventsRespectProgress" ?
        requested :
        "all";

    if (scope === "acceptInvitesProgress") {
      const reset = await resetAcceptInvitesProgress(db, uid);
      logger.info("Onboarding Challenge A progress reset for testing", {
        uid,
        reset,
      });
      return {scope, deleted: reset};
    }

    if (scope === "eventsRespectProgress") {
      const reset = await resetEventsRespectProgress(db, uid);
      logger.info("Onboarding Challenge B Module 4 reset for testing", {
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

    // The Respect grant marker outlives a full reset (see the file
    // header): the ledger is cut back to just that instead of deleted.
    const ledgerRef = db.collection("onboarding_state").doc(uid);
    const ledgerSnap = await ledgerRef.get();
    if (ledgerSnap.exists) {
      const respectGrant = ledgerSnap.data()?.respectGrant;
      if (respectGrant) {
        await ledgerRef.set({uid, respectGrant});
        deleted.push(`${ledgerRef.path} (kept respectGrant)`);
      } else {
        await ledgerRef.delete();
        deleted.push(ledgerRef.path);
      }
    }

    logger.info("Onboarding reset for testing", {uid, deleted});

    return {scope, deleted};
  }
);
