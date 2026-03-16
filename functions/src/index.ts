import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

admin.initializeApp();

export const onParticipantProgressUpdate = onDocumentUpdated(
  {
    document: "competitions/{competitionId}/participants/{participantId}",
    maxInstances: 5,
    concurrency: 1,
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) {
      logger.info("Missing data");
      return;
    }

    const beforeProgress = before.progress ?? 0;
    const afterProgress = after.progress ?? 0;

    if (beforeProgress === afterProgress) {
      logger.info("Progress did not change");
      return;
    }

    if (afterProgress < beforeProgress) {
      logger.info("Progress decreased, skipping notification", {
        competitionId: event.params.competitionId,
        participantId: event.params.participantId,
        beforeProgress,
        afterProgress,
      });
      return;
    }

    const competitionId = event.params.competitionId;
    const updaterUid = after.uid;
    const updaterUsername = after.username ?? "Someone";

    if (!updaterUid) {
      logger.info("Missing updater uid");
      return;
    }

    logger.info("Progress changed!", {
      competitionId,
      participantId: event.params.participantId,
      beforeProgress,
      afterProgress,
      updaterUid,
    });

    const db = admin.firestore();

    const competitionRef = db.collection("competitions").doc(competitionId);
    const competitionSnap = await competitionRef.get();

    if (!competitionSnap.exists) {
      logger.info("Competition not found", {competitionId});
      return;
    }

    const competitionData = competitionSnap.data() || {};
    const competitionTitle = competitionData.title ?? "Competition";

    const participantsSnap = await competitionRef
      .collection("participants").get();

    const otherParticipantUids = participantsSnap.docs
      .map((doc) => doc.data().uid as string | undefined)
      .filter((uid): uid is string => !!uid && uid !== updaterUid);

    if (otherParticipantUids.length === 0) {
      logger.info("No other participants to notify", {competitionId});
      return;
    }

    const uniqueUids = [...new Set(otherParticipantUids)];

    const userDocs = await Promise.all(
      uniqueUids.map((uid) => db.collection("users").doc(uid).get())
    );

    const tokens: string[] = [];

    userDocs.forEach((userSnap) => {
      if (!userSnap.exists) return;

      const userData = userSnap.data();
      const userTokens = userData?.fcmTokens;

      if (Array.isArray(userTokens)) {
        userTokens.forEach((token) => {
          if (typeof token === "string" && token.trim()) {
            tokens.push(token);
          }
        });
      }
    });

    const uniqueTokens = [...new Set(tokens)];

    if (uniqueTokens.length === 0) {
      logger.info("No FCM tokens found for other participants", {
        competitionId,
        uniqueUids,
      });
      return;
    }

    const message: admin.messaging.MulticastMessage = {
      tokens: uniqueTokens,
      notification: {
        title: "Competition update",
        body: `${updaterUsername} updated progress in ${competitionTitle}`,
      },
      data: {
        type: "competition_progress",
        competitionId,
        updaterUid,
      },
    };

    const response = await admin.messaging().sendEachForMulticast(message);

    logger.info("Notifications sent", {
      competitionId,
      successCount: response.successCount,
      failureCount: response.failureCount,
      tokenCount: uniqueTokens.length,
    });

    const invalidTokens: string[] = [];

    response.responses.forEach((resp, index) => {
      if (!resp.success) {
        const errorCode = resp.error?.code ?? "";
        logger.error("FCM send error", {
          token: uniqueTokens[index],
          errorCode,
          errorMessage: resp.error?.message,
        });

        if (
          errorCode === "messaging/invalid-registration-token" ||
          errorCode === "messaging/registration-token-not-registered"
        ) {
          invalidTokens.push(uniqueTokens[index]);
        }
      }
    });

    if (invalidTokens.length > 0) {
      await Promise.all(
        uniqueUids.map(async (uid) => {
          const userRef = db.collection("users").doc(uid);
          await userRef.update({
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
          });
        })
      );

      logger.info("Removed invalid tokens", {
        invalidTokenCount: invalidTokens.length,
      });
    }
  },
);
