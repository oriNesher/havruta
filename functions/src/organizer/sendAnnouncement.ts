import {onCall} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {persistEventDrafts} from "../events/persist";
import {pushToUsers} from "../notifications/push";
import {asCallable, loadAsOrganizer, requireCaller} from "./access";
import {announcementPushBody, planAnnouncement} from "./announcement";

interface SendAnnouncementRequest {
  competitionId: string;
  text: string;
}

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * An organizer's message to everyone in the challenge, delivered three
 * ways: an announcements/{id} doc (the history participants see on
 * Challenge Details), an "announcement" event (the Home card's activity
 * feed, for everyone but the sender), and a push to every device of every
 * member. Rate-limited per challenge so it stays signal, not noise.
 */
export const sendAnnouncement = onCall<SendAnnouncementRequest>(
  {maxInstances: 5},
  (request) => asCallable(async () => {
    const {uid, competitionId} = requireCaller(request);
    const db = admin.firestore();

    const sent = await db.runTransaction(async (tx) => {
      const ctx = await loadAsOrganizer(tx, competitionId, uid);
      const recent = await tx.get(ctx.ref.collection("announcements")
        .where("createdAt", ">",
          admin.firestore.Timestamp.fromMillis(Date.now() - DAY_MS)));
      const text = planAnnouncement(request.data?.text, recent.size);

      const ref = ctx.ref.collection("announcements").doc();
      tx.set(ref, {
        text,
        byUid: ctx.actorUid,
        byUsername: ctx.actorUsername,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {
        id: ref.id,
        text,
        title: typeof ctx.data.title === "string" && ctx.data.title ?
          ctx.data.title :
          "Challenge",
        actorUsername: ctx.actorUsername,
        recipients: [...new Set([
          ...ctx.challenge.participantUids,
          ...ctx.challenge.organizerUids,
        ])].filter((member) => member !== uid),
      };
    });

    await persistEventDrafts(competitionId, [{
      type: "announcement",
      recipients: sent.recipients,
      target: {kind: "create"},
      payload: {
        competitionTitle: sent.title,
        actorUid: uid,
        actorUsername: sent.actorUsername,
        targetUid: null,
        targetUsername: null,
        metadata: {text: sent.text, announcementId: sent.id},
      },
    }]);

    let push = {tokenCount: 0, successCount: 0, failureCount: 0};
    try {
      push = await pushToUsers(
        sent.recipients,
        {
          title: sent.title,
          body: announcementPushBody(sent.actorUsername, sent.text),
        },
        {type: "announcement", competitionId, announcementId: sent.id}
      );
    } catch (error) {
      // The announcement itself is already delivered in-app.
      logger.error("Announcement push failed", {competitionId, error});
    }

    logger.info("Announcement sent", {
      competitionId,
      uid,
      recipients: sent.recipients.length,
      push,
    });
    return {
      announcementId: sent.id,
      recipientCount: sent.recipients.length,
      pushedDevices: push.successCount,
    };
  })
);
