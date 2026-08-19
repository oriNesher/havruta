import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {buildEventsContext} from "./events/context";
import {detectProgressEvents} from "./events/rules/progress";
import {detectRankingEvents} from "./events/rules/ranking";
import {detectGapEvents} from "./events/rules/gap";
import {detectProgressionEvents} from "./events/rules/progression";
import {detectStreakEvents} from "./events/rules/streak";
import {detectFirstBloodEvents} from "./events/rules/firstBlood";
import {
  shouldCreateJoinedEvent,
  shouldCreateLeftEvent,
} from "./events/rules/lifecycle";
import {EventDraft} from "./events/types";
import {persistEventDrafts, persistParticipantStreak} from "./events/persist";
import {createInvite} from "./invites/createInvite";
import {getInvite} from "./invites/getInvite";
import {redeemInvite} from "./invites/redeemInvite";
import {revokeInvite} from "./invites/revokeInvite";
import {
  onInviteLinkRedemptionCreated,
} from "./invites/onInviteLinkRedemptionCreated";
import {inviteLanding} from "./invites/landingHandler";

admin.initializeApp();

export {createInvite, getInvite, redeemInvite, revokeInvite,
  onInviteLinkRedemptionCreated, inviteLanding};

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

    if (!before || !after) {
      logger.info("Missing data for event creation");
      return;
    }

    const context = await buildEventsContext({
      competitionId: event.params.competitionId,
      participantId: event.params.participantId,
      before,
      after,
    });

    if (!context) {
      return;
    }

    const rankingDrafts = detectRankingEvents(context);
    const gapDrafts = detectGapEvents(context);
    const progressionDrafts = detectProgressionEvents(context);
    const streakDrafts = detectStreakEvents(context);
    const firstBloodDrafts = detectFirstBloodEvents(context);

    const drafts = [
      ...detectProgressEvents(context),
      ...rankingDrafts,
      ...gapDrafts,
      ...progressionDrafts,
      ...streakDrafts,
      ...firstBloodDrafts,
    ];

    await persistEventDrafts(context.competitionId, drafts);
    await persistParticipantStreak(
      context.competitionId,
      event.params.participantId,
      context
    );

    logger.info("Events processed", {
      competitionId: context.competitionId,
      actorUid: context.actorUid,
      draftCount: drafts.length,
    });
  },
);

export const onParticipantJoinCreateEvents = onDocumentCreated(
  {
    document: "competitions/{competitionId}/participants/{participantId}",
    maxInstances: 5,
    concurrency: 1,
  },
  async (event) => {
    const participantData = event.data?.data();
    const participantUid = participantData?.uid as string | undefined;

    if (!participantUid) {
      logger.info("Missing participant uid for join event creation");
      return;
    }

    const competitionId = event.params.competitionId;
    const db = admin.firestore();
    const competitionRef = db.collection("competitions").doc(competitionId);
    const competitionSnap = await competitionRef.get();

    if (!competitionSnap.exists) {
      logger.info("Competition not found for join event creation", {
        competitionId,
      });
      return;
    }

    const competitionData = competitionSnap.data() || {};
    const competitionCreatedBy = competitionData.createdBy as
      | string
      | undefined;

    if (!shouldCreateJoinedEvent(participantUid, competitionCreatedBy)) {
      logger.info("Participant seeded at creation, skipping join event", {
        competitionId,
        participantUid,
      });
      return;
    }

    const participantsSnap = await competitionRef
      .collection("participants")
      .get();

    const recipients = [
      ...new Set(
        participantsSnap.docs
          .map((doc) => doc.data().uid as string | undefined)
          .filter((uid): uid is string => !!uid && uid !== participantUid)
      ),
    ];

    const draft: EventDraft = {
      type: "joined",
      recipients,
      target: {kind: "create"},
      payload: {
        competitionTitle: competitionData.title ?? "Competition",
        actorUid: participantUid,
        actorUsername: participantData?.username ?? "Someone",
        targetUid: null,
        targetUsername: null,
        metadata: {},
      },
    };

    await persistEventDrafts(competitionId, [draft]);

    logger.info("Joined event processed", {competitionId, participantUid});
  },
);

export const onParticipantLeaveCreateEvents = onDocumentDeleted(
  {
    document: "competitions/{competitionId}/participants/{participantId}",
    maxInstances: 5,
    concurrency: 1,
  },
  async (event) => {
    const participantData = event.data?.data();
    const participantUid = participantData?.uid as string | undefined;

    if (!participantUid) {
      logger.info("Missing participant uid for left event creation");
      return;
    }

    const competitionId = event.params.competitionId;
    const db = admin.firestore();
    const competitionRef = db.collection("competitions").doc(competitionId);
    const competitionSnap = await competitionRef.get();

    if (!shouldCreateLeftEvent(competitionSnap.exists)) {
      logger.info(
        "Competition no longer exists, skipping left event",
        {competitionId, participantUid}
      );
      return;
    }

    const competitionData = competitionSnap.data() || {};

    const participantsSnap = await competitionRef
      .collection("participants")
      .get();

    const recipients = [
      ...new Set(
        participantsSnap.docs
          .map((doc) => doc.data().uid as string | undefined)
          .filter((uid): uid is string => !!uid && uid !== participantUid)
      ),
    ];

    const draft: EventDraft = {
      type: "left",
      recipients,
      target: {kind: "create"},
      payload: {
        competitionTitle: competitionData.title ?? "Competition",
        actorUid: participantUid,
        actorUsername: participantData?.username ?? "Someone",
        targetUid: null,
        targetUsername: null,
        metadata: {},
      },
    };

    await persistEventDrafts(competitionId, [draft]);

    logger.info("Left event processed", {competitionId, participantUid});
  },
);
