import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

interface GiveRespectRequest {
  competitionId: string;
  eventId: string;
}

// Runs server-side so the sender's balance decrement, the once-per-event
// guard, and the recipient's received-total increment land atomically, and
// so a client can't just write itself an unearned respectGivenBy entry or
// spend respect it doesn't have — see functions/src/invites/redeemInvite.ts
// for the same onCall + transaction shape used elsewhere for a
// currency-like, must-not-race write.
export const giveRespect = onCall<GiveRespectRequest>(
  {maxInstances: 5},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const {competitionId, eventId} = request.data ?? {};
    if (!competitionId || typeof competitionId !== "string") {
      throw new HttpsError("invalid-argument", "competitionId is required.");
    }
    if (!eventId || typeof eventId !== "string") {
      throw new HttpsError("invalid-argument", "eventId is required.");
    }

    const db = admin.firestore();
    const eventRef = db
      .collection("competitions")
      .doc(competitionId)
      .collection("events")
      .doc(eventId);
    const userRef = db.collection("users").doc(uid);

    const balance = await db.runTransaction(async (tx) => {
      const [eventSnap, userSnap] = await Promise.all([
        tx.get(eventRef),
        tx.get(userRef),
      ]);

      if (!eventSnap.exists) {
        throw new HttpsError("not-found", "This event no longer exists.");
      }

      const eventData = eventSnap.data() || {};
      const actorUid = eventData.actorUid as string | undefined;

      if (!actorUid) {
        throw new HttpsError(
          "failed-precondition",
          "This event has no recipient."
        );
      }
      if (actorUid === uid) {
        throw new HttpsError(
          "failed-precondition",
          "You can't give Respect to your own event."
        );
      }

      const givenBy = (eventData.respectGivenBy as string[]) ?? [];
      if (givenBy.includes(uid)) {
        throw new HttpsError(
          "already-exists",
          "You already gave Respect to this event."
        );
      }

      const currentBalance = (userSnap.data()?.respectBalance as number) ?? 0;
      if (currentBalance < 1) {
        throw new HttpsError("failed-precondition", "Not enough Respect.");
      }

      const callerUsername = userSnap.data()?.username ?? "Someone";
      const newBalance = currentBalance - 1;

      tx.update(userRef, {respectBalance: newBalance});
      tx.update(eventRef, {
        respectGivenBy: admin.firestore.FieldValue.arrayUnion(uid),
      });

      const actorRef = db.collection("users").doc(actorUid);
      tx.update(actorRef, {
        totalRespectReceived: admin.firestore.FieldValue.increment(1),
      });

      const notificationRef = actorRef.collection("respectNotifications").doc();
      tx.set(notificationRef, {
        fromUid: uid,
        fromUsername: callerUsername,
        competitionId,
        competitionTitle: eventData.competitionTitle ?? "Competition",
        eventId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return newBalance;
    });

    logger.info("Respect given", {uid, competitionId, eventId});

    return {balance};
  }
);
