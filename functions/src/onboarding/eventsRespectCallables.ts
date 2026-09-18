// The two narrowly scoped server actions behind onboarding Module 4
// (Events and Respect). Neither takes any client input beyond the caller's
// identity: which challenge, which participant, and how much are all fixed
// here, so the client can't use them to act as the system user anywhere
// else or to move Havruta's progress past its one scripted step.

import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {SYSTEM_USER_UID, onboardingCompetitionId} from "./config";
import {
  ONBOARDING_RESPECT_GRANT,
  challengeFriendsProblem,
  decideRespectGrant,
  decideSystemProgress,
  isSystemOnboardingProgressEvent,
} from "./eventsRespect";

/**
 * Document references for the caller's Challenge B and its Module 4 state.
 * @param {FirebaseFirestore.Firestore} db The Firestore instance.
 * @param {string} uid The calling user's uid.
 * @return {object} The refs every Module 4 action reads.
 */
function challengeFriendsRefs(db: FirebaseFirestore.Firestore, uid: string) {
  const competition = db
    .collection("competitions")
    .doc(onboardingCompetitionId(uid, "challengeFriends"));
  return {
    competition,
    systemParticipant: competition
      .collection("participants")
      .doc(SYSTEM_USER_UID),
    callerParticipant: competition.collection("participants").doc(uid),
    ledger: db.collection("onboarding_state").doc(uid),
  };
}

/**
 * Makes the system user "Havruta" perform its one onboarding progress
 * update in the caller's Challenge B (0 -> 1 of 2 friends): the same
 * participant-doc write a real Add Progress makes (progress increment +
 * updatedAt), so onParticipantProgressCreateEvents builds the resulting
 * Event through the normal pipeline — no event is written here.
 *
 * Idempotent: one transaction re-reads the server-owned ledger and the
 * system participant, and applies the increment only if neither shows it
 * already happened, recording that in the ledger in the same commit.
 * Concurrent or retried calls serialize on those documents, so Havruta can
 * never reach 2 through this callable.
 */
export const ensureOnboardingSystemProgress = onCall(
  {maxInstances: 5},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const db = admin.firestore();
    const refs = challengeFriendsRefs(db, uid);

    const outcome = await db.runTransaction(async (tx) => {
      const [competition, systemParticipant, callerParticipant, ledger] =
        await Promise.all([
          tx.get(refs.competition),
          tx.get(refs.systemParticipant),
          tx.get(refs.callerParticipant),
          tx.get(refs.ledger),
        ]);

      const problem = challengeFriendsProblem(
        uid,
        competition.data(),
        systemParticipant.data(),
        callerParticipant.data()
      );
      if (problem) {
        throw new HttpsError("failed-precondition", problem);
      }

      const ledgerEventsRespect = ledger.data()?.eventsRespect;
      const decision = decideSystemProgress(
        ledgerEventsRespect,
        systemParticipant.data()
      );

      if (decision === "apply") {
        // Exactly the shape FirestoreService.addProgress writes.
        tx.update(refs.systemParticipant, {
          progress: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      if (decision === "apply" ||
        !ledgerEventsRespect?.systemProgressAppliedAt) {
        tx.set(refs.ledger, {
          eventsRespect: {
            competitionId: refs.competition.id,
            systemProgressAppliedAt: FieldValue.serverTimestamp(),
          },
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
      return decision;
    });

    logger.info("Onboarding system progress", {uid, outcome});
    return {
      competitionId: refs.competition.id,
      applied: outcome === "apply",
    };
  }
);

/**
 * Makes sure the caller can give the one Respect Module 4 asks for: if
 * their balance is empty, adds ONBOARDING_RESPECT_GRANT to respectBalance
 * (and nothing else — totalRespectReceived is untouched, since nobody gave
 * it to them). At most once per user ever: the marker lives in the
 * server-only onboarding_state ledger, which clients can't write and test
 * resets preserve, and the grant is refused once the user has already
 * given Havruta's onboarding event its Respect.
 */
export const ensureOnboardingRespect = onCall(
  {maxInstances: 5},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const db = admin.firestore();
    const refs = challengeFriendsRefs(db, uid);
    const userRef = db.collection("users").doc(uid);
    const systemEventsQuery = refs.competition
      .collection("events")
      .where("actorUid", "==", SYSTEM_USER_UID)
      .where("type", "==", "progress");

    const result = await db.runTransaction(async (tx) => {
      const [
        competition,
        systemParticipant,
        callerParticipant,
        ledger,
        user,
        systemEvents,
      ] = await Promise.all([
        tx.get(refs.competition),
        tx.get(refs.systemParticipant),
        tx.get(refs.callerParticipant),
        tx.get(refs.ledger),
        tx.get(userRef),
        tx.get(systemEventsQuery),
      ]);

      const problem = challengeFriendsProblem(
        uid,
        competition.data(),
        systemParticipant.data(),
        callerParticipant.data()
      );
      if (problem) {
        throw new HttpsError("failed-precondition", problem);
      }
      if (!user.exists) {
        throw new HttpsError("failed-precondition", "No user profile.");
      }

      const balance = (user.data()?.respectBalance as number) ?? 0;
      const decision = decideRespectGrant({
        balance,
        ledgerRespectGrant: ledger.data()?.respectGrant,
        systemProgressApplied:
          decideSystemProgress(
            ledger.data()?.eventsRespect,
            systemParticipant.data()
          ) === "alreadyApplied",
        alreadyGaveRespect: systemEvents.docs.some((doc) =>
          isSystemOnboardingProgressEvent(doc.data()) &&
          ((doc.data().respectGivenBy as string[] | undefined) ?? [])
            .includes(uid)
        ),
      });

      if (decision !== "grant") return {decision, balance};

      tx.update(userRef, {
        respectBalance: FieldValue.increment(ONBOARDING_RESPECT_GRANT),
      });
      tx.set(refs.ledger, {
        respectGrant: {
          amount: ONBOARDING_RESPECT_GRANT,
          competitionId: refs.competition.id,
          grantedAt: FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return {decision, balance: balance + ONBOARDING_RESPECT_GRANT};
    });

    logger.info("Onboarding Respect grant", {uid, ...result});
    return result;
  }
);
