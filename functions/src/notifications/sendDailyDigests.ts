import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {challengeDayKey} from "../challenges/calendar";
import {isLargeChallenge, parseChallenge} from "../challenges/model";
import {toStandingParticipant} from "../challenges/standings";
import {buildDigest, DIGEST_HOUR, localHour} from "./digest";
import {pushEach, UserMessage} from "./push";

/**
 * Hourly: for every running large challenge whose local time is
 * DIGEST_HOUR, sends that day's digest — once (a transaction on
 * competitions/{id}/digest/state claims the day, so overlapping or retried
 * runs never send twice). Goes to participants and organizers who haven't
 * opened the app today; whoever has already seen the day in the app gets
 * nothing.
 */
export const sendDailyDigests = onSchedule(
  {schedule: "every 60 minutes", maxInstances: 1, timeoutSeconds: 300},
  async () => {
    const db = admin.firestore();
    const nowMillis = Date.now();
    const active = await db.collection("competitions")
      .where("status", "==", "active").get();

    const due = active.docs.filter((doc) => {
      const challenge = parseChallenge(doc.data());
      return isLargeChallenge(challenge) &&
        localHour(nowMillis, challenge.timeZone) === DIGEST_HOUR;
    });

    const results = await Promise.allSettled(due.map((doc) =>
      sendDigest(doc.ref, nowMillis)));
    for (const failure of results.filter((r) => r.status === "rejected")) {
      logger.error("Sending a digest failed", {
        reason: (failure as PromiseRejectedResult).reason,
      });
    }
    logger.info("Daily digests processed", {due: due.length});
  }
);

/**
 * Claims today's digest for one challenge and sends it.
 * @param {FirebaseFirestore.DocumentReference} ref The challenge.
 * @param {number} nowMillis The current time.
 * @return {Promise<void>} Resolves once sent (or skipped).
 */
async function sendDigest(
  ref: FirebaseFirestore.DocumentReference,
  nowMillis: number
): Promise<void> {
  const db = admin.firestore();
  const stateRef = ref.collection("digest").doc("state");

  const claimed = await db.runTransaction(async (tx) => {
    const [snap, stateSnap, participantsSnap] = await Promise.all([
      tx.get(ref),
      tx.get(stateRef),
      tx.get(ref.collection("participants")),
    ]);
    const challenge = parseChallenge(snap.data() ?? {});
    const todayKey = challengeDayKey(nowMillis, challenge.timeZone);
    const state = stateSnap.data() ?? {};
    if (state.day === todayKey) return null;

    const digest = buildDigest({
      title: typeof snap.data()?.title === "string" ?
        snap.data()?.title : "Challenge",
      challenge,
      participants: participantsSnap.docs
        .map((doc) => toStandingParticipant(doc.data(), challenge))
        .filter((p) => !!p.uid),
      todayKey,
      previousRanks: (state.ranks ?? {}) as Record<string, number>,
    });
    tx.set(stateRef, {
      day: todayKey,
      ranks: digest.ranks,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {digest, todayKey, organizerUids: challenge.organizerUids};
  });
  if (!claimed) return;

  const {digest, todayKey, organizerUids} = claimed;
  const recipients = [...new Set([
    ...Object.keys(digest.bodies),
    ...organizerUids,
  ])];
  const users = recipients.length === 0 ? [] : await db.getAll(
    ...recipients.map((uid) => db.collection("users").doc(uid)));
  const openedToday = new Set(users
    .filter((u) => u.data()?.lastOpenedDate === todayKey)
    .map((u) => u.id));

  const messages: UserMessage[] = recipients
    .filter((uid) => !openedToday.has(uid))
    .map((uid) => ({
      uid,
      title: digest.title,
      body: digest.bodies[uid] ?? digest.summary,
      data: {type: "daily_digest", competitionId: ref.id},
    }));
  const result = await pushEach(messages);
  logger.info("Digest sent", {
    competitionId: ref.id,
    recipients: messages.length,
    skippedOpenedToday: openedToday.size,
    result,
  });
}
