import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {persistEventDrafts} from "../events/persist";
import {
  detectEliminationEvents,
  detectPlacementEvents,
} from "../events/rules/outcome";
import {EventDraft} from "../events/types";
import {parseChallenge} from "./model";
import {aggressorApplies, aggressorWindow} from "./aggressor";
import {settleAggressor} from "./settleAggressor";
import {toStandingParticipant} from "./standings";
import {decideDeadlineResult} from "./winConditions/deadline";
import {evaluateLastStanding} from "./winConditions/lastStanding";

/**
 * Judges one Last One Standing challenge: eliminations for every day that
 * has ended since the last run, and the winner once decided. The
 * competition-doc cursor (lastEvaluatedDay) and the eliminations commit in
 * one transaction, so overlapping or retried runs never judge a day twice.
 * @param {FirebaseFirestore.DocumentReference} ref The competition doc.
 * @param {number} nowMillis The current time.
 * @return {Promise<void>} Resolves once written and announced.
 */
async function settleLastStanding(
  ref: FirebaseFirestore.DocumentReference,
  nowMillis: number
): Promise<void> {
  const db = admin.firestore();

  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return null;
    const challenge = parseChallenge(snap.data() ?? {});
    const participantsSnap = await tx.get(ref.collection("participants"));
    const participants = participantsSnap.docs
      .map((doc) => toStandingParticipant(doc.data(), challenge))
      .filter((p) => !!p.uid);

    const result = evaluateLastStanding(challenge, participants, nowMillis);
    if (!result.update) return null;

    tx.update(ref, {
      ...result.update,
      ...(result.completes ?
        {completedAt: admin.firestore.FieldValue.serverTimestamp()} :
        {}),
    });
    for (const elimination of result.eliminations) {
      tx.update(ref.collection("participants").doc(elimination.uid), {
        eliminatedOnDay: elimination.day,
        eliminatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return {title: snap.data()?.title ?? "Challenge", participants, result};
  });

  if (!outcome) return;
  const {title, participants, result} = outcome;

  const drafts: EventDraft[] = [
    ...detectEliminationEvents(title, participants, result.eliminations),
    ...detectPlacementEvents(
      title,
      participants,
      result.winnerUids.map((uid) => ({uid, position: 1}))
    ),
  ];
  await persistEventDrafts(ref.id, drafts);

  logger.info("Last One Standing settled", {
    competitionId: ref.id,
    eliminated: result.eliminations.map((e) => e.uid),
    completes: result.completes,
    winnerUids: result.winnerUids,
  });
}

/**
 * Completes one Race or Most Progress challenge whose end time has passed,
 * recording its winner(s) — inside a transaction that only proceeds while
 * the challenge is still active, so it settles exactly once.
 * @param {FirebaseFirestore.DocumentReference} ref The competition doc.
 * @param {number} nowMillis The current time.
 * @return {Promise<void>} Resolves once written and announced.
 */
async function settleDeadline(
  ref: FirebaseFirestore.DocumentReference,
  nowMillis: number
): Promise<void> {
  const db = admin.firestore();

  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return null;
    const challenge = parseChallenge(snap.data() ?? {});
    if (
      challenge.status !== "active" ||
      challenge.winCondition === "lastStanding" ||
      !challenge.endsAt ||
      challenge.endsAt.toMillis() > nowMillis
    ) {
      return null;
    }

    const participantsSnap = await tx.get(ref.collection("participants"));
    const participants = participantsSnap.docs
      .map((doc) => toStandingParticipant(doc.data(), challenge))
      .filter((p) => !!p.uid);
    const result = decideDeadlineResult(challenge, participants);

    tx.update(ref, {
      status: "completed",
      winnerUids: result.winnerUids,
      winnerUid: result.winnerUids[0] ?? null,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {title: snap.data()?.title ?? "Challenge", participants, result};
  });

  if (!outcome) return;
  const {title, participants, result} = outcome;

  await persistEventDrafts(
    ref.id,
    detectPlacementEvents(title, participants, result.placements)
  );

  logger.info("Challenge ended at its deadline", {
    competitionId: ref.id,
    winnerUids: result.winnerUids,
  });
}

/**
 * Hourly: judges Last One Standing days that have ended (in each
 * challenge's own time zone, so the hour after local midnight is when a
 * day's eliminations land) and completes challenges past their end time.
 * Each challenge settles in its own transaction; one failing doesn't stop
 * the rest.
 */
export const settleChallenges = onSchedule(
  {schedule: "every 60 minutes", maxInstances: 1, timeoutSeconds: 300},
  async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const nowMillis = now.toMillis();

    const [lastStandingSnap, endedSnap] = await Promise.all([
      db.collection("competitions")
        .where("winCondition", "==", "lastStanding")
        .where("status", "==", "active")
        .get(),
      db.collection("competitions")
        .where("status", "==", "active")
        .where("endsAt", "<=", now)
        .get(),
    ]);

    const jobs = [
      ...lastStandingSnap.docs.map((doc) =>
        settleLastStanding(doc.ref, nowMillis)),
      ...endedSnap.docs
        .filter((doc) => doc.data().winCondition !== "lastStanding")
        .map((doc) => settleDeadline(doc.ref, nowMillis)),
    ];

    const results = await Promise.allSettled(jobs);
    const failures = results.filter((r) => r.status === "rejected");
    for (const failure of failures) {
      logger.error("Settling a challenge failed", {
        reason: (failure as PromiseRejectedResult).reason,
      });
    }

    // After the settling above, so a holder eliminated at midnight loses
    // the badge in this same run, and a challenge that just ended keeps
    // its final holder (settleAggressor skips anything no longer active).
    const rolledOver = await rollOverAggressorBadges(nowMillis);

    logger.info("Challenges settled", {
      lastStanding: lastStandingSnap.size,
      ended: endedSnap.size,
      failures: failures.length,
      aggressorRollovers: rolledOver,
    });
  }
);

/**
 * Re-decides the Aggressor Badge of every running challenge whose badge
 * window has moved on to a new challenge day since it was last decided —
 * otherwise a holder whose progress has aged out of the window would keep
 * it until someone next logs progress. Filtering on the stored
 * evaluatedDay means each challenge is re-read once a day (the run after
 * its local midnight), not every hour.
 * @param {number} nowMillis The current time.
 * @return {Promise<number>} How many challenges were re-decided.
 */
async function rollOverAggressorBadges(nowMillis: number): Promise<number> {
  const activeSnap = await admin.firestore()
    .collection("competitions")
    .where("status", "==", "active")
    .get();

  const due = activeSnap.docs.filter((doc) => {
    const data = doc.data();
    const challenge = parseChallenge(data);
    const isOnboarding = data.onboarding?.isOnboarding === true;
    return aggressorApplies(challenge, isOnboarding) &&
      challenge.aggressor.evaluatedDay !==
        aggressorWindow(challenge, nowMillis)[0];
  });

  const results = await Promise.allSettled(
    due.map((doc) => settleAggressor(doc.id, "dayRollover", null))
  );
  for (const failure of results.filter((r) => r.status === "rejected")) {
    logger.error("Rolling over an Aggressor Badge failed", {
      reason: (failure as PromiseRejectedResult).reason,
    });
  }
  return due.length;
}
