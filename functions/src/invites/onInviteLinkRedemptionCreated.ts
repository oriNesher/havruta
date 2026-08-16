import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

// Notifies the link's creator specifically ("X joined via your link") —
// distinct from onParticipantJoinCreateEvents, which notifies all other
// participants generally. Mirrors onParticipantProgressUpdate's FCM pattern.
export const onInviteLinkRedemptionCreated = onDocumentCreated(
  {
    document: "challenge_invite_links/{linkId}/redemptions/{uid}",
    maxInstances: 5,
    concurrency: 1,
  },
  async (event) => {
    const redemptionData = event.data?.data();
    if (!redemptionData) {
      logger.info("Missing redemption data");
      return;
    }

    const db = admin.firestore();
    const linkRef = db
      .collection("challenge_invite_links")
      .doc(event.params.linkId);
    const linkSnap = await linkRef.get();

    if (!linkSnap.exists) {
      logger.info("Invite link not found", {linkId: event.params.linkId});
      return;
    }

    const linkData = linkSnap.data() || {};
    const creatorUid = linkData.createdBy as string | undefined;
    const redeemerUsername = redemptionData.username ?? "Someone";
    const competitionTitle = linkData.competitionTitle ?? "your challenge";

    if (!creatorUid || creatorUid === event.params.uid) {
      // No creator on record, or the creator redeeming their own link.
      return;
    }

    const creatorSnap = await db.collection("users").doc(creatorUid).get();
    const tokens = (creatorSnap.data()?.fcmTokens as string[] | undefined) ??
      [];
    const uniqueTokens = [...new Set(tokens)].filter(
      (t) => typeof t === "string" && t.trim()
    );

    if (uniqueTokens.length === 0) {
      logger.info("No FCM tokens for invite link creator", {creatorUid});
      return;
    }

    const message: admin.messaging.MulticastMessage = {
      tokens: uniqueTokens,
      notification: {
        title: "New challenge member",
        body:
          `${redeemerUsername} joined ${competitionTitle} via your invite link`,
      },
      data: {
        type: "invite_link_redeemed",
        competitionId: linkData.competitionId ?? "",
        linkId: event.params.linkId,
      },
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    logger.info("Invite-link join notification sent", {
      creatorUid,
      successCount: response.successCount,
      failureCount: response.failureCount,
    });
  }
);
