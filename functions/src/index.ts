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

export const onParticipantProgressCreateEvents = onDocumentUpdated(
  {
    document: "competitions/{competitionId}/participants/{participantId}",
    maxInstances: 5,
    concurrency: 1,
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    // Exit if event data is missing
    if (!before || !after) {
      logger.info("Missing data for event creation");
      return;
    }

    const beforeProgress = before.progress ?? 0;
    const afterProgress = after.progress ?? 0;

    // Exit if progress did not change
    if (beforeProgress === afterProgress) {
      logger.info(
        "Progress did not change, skipping event creation"
      );
      return;
    }

    // Exit if progress decreased
    if (afterProgress < beforeProgress) {
      logger.info("Progress decreased, skipping event creation", {
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
    const updaterTargetValue = after.targetValue ?? 0;

    // Exit if updater uid is missing
    if (!updaterUid) {
      logger.info("Missing updater uid for event creation");
      return;
    }

    const db = admin.firestore();

    const competitionRef = db.collection("competitions").doc(competitionId);
    const competitionSnap = await competitionRef.get();

    // Exit if competition does not exist
    if (!competitionSnap.exists) {
      logger.info(
        "Competition not found for event creation",
        {competitionId}
      );
      return;
    }

    const competitionData = competitionSnap.data() || {};
    const competitionTitle = competitionData.title ?? "Competition";
    const competitionStatus = competitionData.status ?? "active";

    // Exit if competition is not active
    if (competitionStatus !== "active") {
      logger.info("Competition is not active, skipping event creation", {
        competitionId,
        competitionStatus,
      });
      return;
    }

    const participantsSnap = await competitionRef
      .collection("participants")
      .get();

    const participants = participantsSnap.docs
      .map((doc) => doc.data())
      .filter((participant) => !!participant.uid);

    const participantUids = participants
      .map((participant) => participant.uid as string)
      .filter((uid): uid is string => !!uid);

    const uniqueParticipantUids = [...new Set(participantUids)];

    // Exit if there are not enough participants
    if (uniqueParticipantUids.length < 2) {
      logger.info("Not enough participants for event creation", {
        competitionId,
        participantCount: uniqueParticipantUids.length,
      });
      return;
    }

    // All recipients except the actor himself
    const unseenByUserUids = uniqueParticipantUids.filter(
      (uid) => uid !== updaterUid
    );

    // Look for an existing open progress event for this actor
    const existingEventSnap = await db
      .collection("events")
      .where("type", "==", "progress")
      .where("competitionId", "==", competitionId)
      .where("actorUid", "==", updaterUid)
      .where("status", "==", "open")
      .limit(1)
      .get();

    if (!existingEventSnap.empty) {
      // Update the existing progress event instead of creating a new one
      const eventDoc = existingEventSnap.docs[0];
      const eventData = eventDoc.data();

      const originalBeforeProgress =
        eventData.metadata?.beforeProgress ?? beforeProgress;
      const previousUpdatesCount = eventData.metadata?.updatesCount ?? 1;

      await eventDoc.ref.update({
        competitionTitle,
        "actorUsername": updaterUsername,
        unseenByUserUids,
        "lastUpdatedAt": admin.firestore.FieldValue.serverTimestamp(),
        "metadata.afterProgress": afterProgress,
        "metadata.progressDelta": afterProgress - originalBeforeProgress,
        "metadata.updatesCount": previousUpdatesCount + 1,
      });

      logger.info("Progress event updated", {
        competitionId,
        updaterUid,
        afterProgress,
        unseenByCount: unseenByUserUids.length,
      });
    } else {
      // Create a new open progress event if none exists
      await db.collection("events").add({
        type: "progress",
        status: "open",
        competitionId,
        competitionTitle,
        actorUid: updaterUid,
        actorUsername: updaterUsername,
        targetUid: null,
        targetUsername: null,
        unseenByUserUids,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          beforeProgress,
          afterProgress,
          progressDelta: afterProgress - beforeProgress,
          updatesCount: 1,
        },
      });

      logger.info("Progress event created", {
        competitionId,
        updaterUid,
        beforeProgress,
        afterProgress,
        unseenByCount: unseenByUserUids.length,
      });
    }

    // Skip overtook detection if updater target value is invalid
    if (
      typeof updaterTargetValue !== "number" ||
      updaterTargetValue <= 0
    ) {
      logger.info("Invalid updater target value, skipping overtook detection", {
        competitionId,
        updaterUid,
        updaterTargetValue,
      });
      return;
    }

    const updaterPercentBefore = beforeProgress / updaterTargetValue;
    const updaterPercentAfter = afterProgress / updaterTargetValue;

    const overtookWrites: Promise<FirebaseFirestore.DocumentReference>[] = [];

    for (const participant of participants) {
      const otherUid = participant.uid as string | undefined;

      // Skip the updater himself
      if (!otherUid || otherUid === updaterUid) {
        continue;
      }

      const otherUsername = participant.username ?? "Someone";
      const otherProgress = participant.progress ?? 0;
      const otherTargetValue = participant.targetValue ?? 0;

      // Skip participants with invalid target value
      if (
        typeof otherTargetValue !== "number" ||
        otherTargetValue <= 0
      ) {
        continue;
      }

      const otherPercent = otherProgress / otherTargetValue;

      // Create an overtook event only if the updater was not ahead before
      // and is ahead now after the latest progress update
      const overtookThisParticipant =
        updaterPercentBefore <= otherPercent &&
        updaterPercentAfter > otherPercent;

      if (!overtookThisParticipant) {
        continue;
      }

      overtookWrites.push(
        db.collection("events").add({
          type: "overtook",
          status: "open",
          competitionId,
          competitionTitle,
          actorUid: updaterUid,
          actorUsername: updaterUsername,
          targetUid: otherUid,
          targetUsername: otherUsername,
          unseenByUserUids: [otherUid],
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          metadata: {
            actorProgressBefore: beforeProgress,
            actorProgressAfter: afterProgress,
            actorTargetValue: updaterTargetValue,
            actorPercentBefore: updaterPercentBefore,
            actorPercentAfter: updaterPercentAfter,
            targetProgress: otherProgress,
            targetTargetValue: otherTargetValue,
            targetPercent: otherPercent,
          },
        })
      );
    }

    if (overtookWrites.length > 0) {
      await Promise.all(overtookWrites);

      logger.info("Overtook events created", {
        competitionId,
        updaterUid,
        overtookCount: overtookWrites.length,
      });
    } else {
      logger.info("No overtook events created", {
        competitionId,
        updaterUid,
      });
    }
  },
);
