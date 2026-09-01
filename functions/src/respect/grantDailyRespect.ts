import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {toDateString} from "../events/streakDate";

// Server-authoritative so the grant can't be replayed by a client resending
// a fabricated date string — see functions/src/events/streakDate.ts, already
// used the same way to gate the (server-side) activity streak.
export const grantDailyRespect = onCall(
  {maxInstances: 5},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const db = admin.firestore();
    const userRef = db.collection("users").doc(uid);
    const today = toDateString(admin.firestore.Timestamp.now());

    const balance = await db.runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      const data = snap.data() ?? {};
      const lastGrantDate = data.respectLastGrantDate as string | undefined;
      const currentBalance = (data.respectBalance as number) ?? 0;

      if (lastGrantDate === today) {
        return currentBalance;
      }

      const newBalance = currentBalance + 1;
      tx.update(userRef, {
        respectBalance: newBalance,
        respectLastGrantDate: today,
      });
      return newBalance;
    });

    logger.info("Daily respect grant processed", {uid, today, balance});

    return {balance};
  }
);
