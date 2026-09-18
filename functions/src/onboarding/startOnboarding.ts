import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {
  ONBOARDING_CHALLENGES,
  ONBOARDING_VERSION,
  OnboardingChallengeConfig,
  OnboardingChallengeKey,
  SYSTEM_USER_UID,
  SYSTEM_USERNAME,
  onboardingCompetitionId,
  onboardingInviteId,
} from "./config";
import {ensureSystemUserDoc} from "./ensureSystemUser";

interface OnboardingChallengeResult {
  competitionId: string;
  inviteId: string;
}

/**
 * Idempotently creates or reuses one onboarding challenge and its invite to
 * the given user, inside a single transaction. Every write is guarded by a
 * tx.get() existence check on a *deterministic* document id (see
 * onboardingCompetitionId/onboardingInviteId), so calling this again after
 * a crash, a network retry, or a duplicate callable invocation always
 * converges on the same documents rather than creating new ones — even if
 * this challenge previously partially failed (e.g. the competition was
 * created but the invite write never landed) or the *other* onboarding
 * challenge failed while this one succeeded.
 * @param {FirebaseFirestore.Firestore} db The Firestore instance.
 * @param {string} uid The new user's uid onboarding is being run for.
 * @param {string} toUsername The new user's display username, for the
 *   invite doc's toUsername field.
 * @param {OnboardingChallengeConfig} config Which onboarding challenge to
 *   create or reuse.
 * @return {Promise<OnboardingChallengeResult>} The competition and invite
 *   document ids, whether just created or already existing.
 */
async function ensureOnboardingChallenge(
  db: FirebaseFirestore.Firestore,
  uid: string,
  toUsername: string,
  config: OnboardingChallengeConfig
): Promise<OnboardingChallengeResult> {
  const competitionRef = db
    .collection("competitions")
    .doc(onboardingCompetitionId(uid, config.key));
  const participantRef = competitionRef
    .collection("participants")
    .doc(SYSTEM_USER_UID);
  const inviteRef = db
    .collection("competition_invites")
    .doc(onboardingInviteId(uid, config.key));

  await db.runTransaction(async (tx) => {
    const [competitionSnap, participantSnap, inviteSnap] = await Promise.all([
      tx.get(competitionRef),
      tx.get(participantRef),
      tx.get(inviteRef),
    ]);

    // Explicit onboarding metadata (not just the challenge title) so this
    // record can be reliably identified, attributed to this user, and
    // excluded from analytics or cleaned up later without guessing from
    // display text.
    const onboardingMeta = {
      isOnboarding: true,
      onboardingChallengeKey: config.key,
      onboardingUserId: uid,
      onboardingVersion: ONBOARDING_VERSION,
    };

    if (!competitionSnap.exists) {
      // Mirrors createSharedGoalCompetition's document shape exactly, so
      // every existing screen reads this like any other shared-goal
      // challenge.
      tx.set(competitionRef, {
        title: config.title,
        description: config.description,
        createdBy: SYSTEM_USER_UID,
        participantUids: [SYSTEM_USER_UID],
        status: "active",
        winnerUid: null,
        type: "sharedGoalChallenge",
        sharedGoalTitle: config.sharedGoalTitle,
        sharedTargetValue: config.sharedTargetValue,
        sharedUnit: config.sharedUnit,
        createdAt: FieldValue.serverTimestamp(),
        onboarding: onboardingMeta,
      });
    }

    if (!participantSnap.exists) {
      // Mirrors createCompetition's creator-participant shape exactly, so
      // this reads like any other challenge's creator to existing screens
      // — and so a later system-authored progress increment here is a
      // normal participant-doc update that the existing
      // onParticipantProgressCreateEvents trigger picks up unmodified.
      tx.set(participantRef, {
        uid: SYSTEM_USER_UID,
        username: SYSTEM_USERNAME,
        goalTitle: config.sharedGoalTitle,
        targetValue: config.sharedTargetValue,
        unit: config.sharedUnit,
        progress: 0,
        joinedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    if (!inviteSnap.exists) {
      // Same shape sendCompetitionInvite writes for a shared-goal
      // challenge, including the sharedGoalTitle/sharedTargetValue/
      // sharedUnit fields the existing shared-goal accept dialog shows and
      // then copies onto the joining participant.
      tx.set(inviteRef, {
        competitionId: competitionRef.id,
        competitionTitle: config.title,
        competitionType: "sharedGoalChallenge",
        fromUid: SYSTEM_USER_UID,
        toUid: uid,
        toUsername,
        status: "pending",
        createdAt: FieldValue.serverTimestamp(),
        sharedGoalTitle: config.sharedGoalTitle,
        sharedTargetValue: config.sharedTargetValue,
        sharedUnit: config.sharedUnit,
        onboarding: onboardingMeta,
      });
    }
  });

  return {competitionId: competitionRef.id, inviteId: inviteRef.id};
}

/**
 * Initializes the system-managed onboarding data for the calling user: two
 * real challenges owned by the "Havruta" system user (see
 * functions/src/onboarding/config.ts), each with a real invitation sent to
 * the caller. Entirely idempotent — safe to call repeatedly (app restart,
 * dropped response, double-tap, retried after a partial failure) without
 * ever creating duplicate challenges or invitations.
 *
 * This only builds the data foundation for onboarding. It does not show
 * any UI, script any later actions, or advance an onboarding session —
 * those are separate, later modules that will call this once and then
 * drive the user through the two real challenges it returns.
 */
export const startOnboarding = onCall(
  {maxInstances: 5},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const db = admin.firestore();

    await ensureSystemUserDoc(db);

    const userSnap = await db.collection("users").doc(uid).get();
    const toUsername = (userSnap.data()?.username as string | undefined) ??
      "there";

    const challenges: Partial<
      Record<OnboardingChallengeKey, OnboardingChallengeResult>
    > = {};

    for (const config of ONBOARDING_CHALLENGES) {
      challenges[config.key] = await ensureOnboardingChallenge(
        db,
        uid,
        toUsername,
        config
      );
    }

    // A single, cheap-to-read ledger for later onboarding modules (the
    // session controller, welcome alert, home checklist, etc.) so they
    // don't need to re-derive challenge/invite ids from a query every time.
    await db.collection("onboarding_state").doc(uid).set(
      {
        uid,
        version: ONBOARDING_VERSION,
        status: "initialized",
        challenges,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    logger.info("Onboarding initialized", {uid, challenges});

    return {challenges};
  }
);
