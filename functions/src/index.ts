import {randomUUID} from "crypto";
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
import {settleRaceFinish} from "./challenges/finish";
import {settleChallenges} from "./challenges/settleChallenges";
import {settleAggressor} from "./challenges/settleAggressor";
import {isLargeChallenge, parseChallenge} from "./challenges/model";
import {audienceFor} from "./events/audience";
import {loadAudience} from "./events/loadAudience";
import {persistEventDrafts} from "./events/persist";
import {
  isOrganizerCorrection,
  keepForCorrection,
} from "./events/corrections";
import {createInvite} from "./invites/createInvite";
import {getInvite} from "./invites/getInvite";
import {redeemInvite} from "./invites/redeemInvite";
import {revokeInvite} from "./invites/revokeInvite";
import {
  onInviteLinkRedemptionCreated,
} from "./invites/onInviteLinkRedemptionCreated";
import {inviteLanding} from "./invites/landingHandler";
import {
  onCompetitionDeletedCleanupInviteLinks,
} from "./invites/onCompetitionDeleted";
import {grantDailyRespect} from "./respect/grantDailyRespect";
import {giveRespect} from "./respect/giveRespect";
import {googleSignInPreflight} from "./auth/googleSignInPreflight";
import {acceptInvite} from "./invites/acceptInvite";
import {findUserByEmail} from "./users/findUserByEmail";
import {syncPublicProfile} from "./users/syncPublicProfile";
import {updateChallengeSettings} from "./organizer/updateChallengeSettings";
import {removeParticipant} from "./organizer/removeParticipant";
import {correctProgress} from "./organizer/correctProgress";
import {endChallengeEarly} from "./organizer/endChallengeEarly";
import {setOrganizers} from "./organizer/setOrganizers";
import {reinstateParticipant} from "./organizer/reinstateParticipant";
import {sendAnnouncement} from "./organizer/sendAnnouncement";
import {sendDailyDigests} from "./notifications/sendDailyDigests";
import {manageTeams} from "./organizer/manageTeams";

admin.initializeApp();

export {createInvite, getInvite, redeemInvite, revokeInvite,
  onInviteLinkRedemptionCreated, inviteLanding,
  onCompetitionDeletedCleanupInviteLinks,
  grantDailyRespect, giveRespect, settleChallenges, googleSignInPreflight,
  acceptInvite, findUserByEmail, syncPublicProfile,
  updateChallengeSettings, removeParticipant, correctProgress,
  endChallengeEarly, setOrganizers, reinstateParticipant, sendAnnouncement,
  sendDailyDigests, manageTeams};

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

    if (isOrganizerCorrection(before, after)) {
      logger.info("Organizer correction, skipping notification", {
        competitionId: event.params.competitionId,
        participantId: event.params.participantId,
      });
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
    const competitionTitle = competitionData.title ?? "Challenge";

    // A large challenge sends no per-report push — at 200 people that's
    // 199 notifications per entry. The daily digest covers it instead.
    if (isLargeChallenge(parseChallenge(competitionData))) {
      logger.info("Large challenge, no per-report push", {competitionId});
      return;
    }

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
        title: "Challenge update",
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

// This trigger sits directly between "user logs progress" and
// "celebration screen appears", so its cold start (a few seconds of
// loading firebase-admin before a single line of rule code runs) is the
// whole perceived delay. A reserved warm instance would remove it, but
// minInstances bills continuously whether or not anyone is using the app
// — not worth it at the current user count. Revisit once traffic makes a
// warm instance cheaper than the wait.
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

    const batchId = randomUUID();
    const beforeProgress = before.progress ?? 0;
    const afterProgress = after.progress ?? 0;
    // An organizer's correction settles outcomes (badge, race finish) like
    // any progress change, but isn't the participant doing something: no
    // celebrations of it, no social events, no streak.
    const correction = isOrganizerCorrection(before, after);

    // The badge settles first, and for decreases too (which skip every
    // other event): a race finish below can complete the challenge, which
    // freezes the badge, and taking progress back can pass it on.
    if (beforeProgress !== afterProgress) {
      try {
        await settleAggressor(
          event.params.competitionId,
          afterProgress > beforeProgress ? "progress" : "progressRemoved",
          correction ? null : after.uid ?? null,
          batchId
        );
      } catch (error) {
        logger.error("Settling the Aggressor Badge failed", {
          competitionId: event.params.competitionId,
          error,
        });
      }
    }

    const context = await buildEventsContext({
      competitionId: event.params.competitionId,
      participantId: event.params.participantId,
      before,
      after,
      countsAsActivity: !correction,
    });

    if (!context) {
      return;
    }

    if (correction) {
      const finishDrafts = await settleRaceFinish(
        context,
        keepForCorrection(detectProgressionEvents(context))
      );
      await persistEventDrafts(context.competitionId, finishDrafts, batchId);
      logger.info("Correction processed", {
        competitionId: context.competitionId,
        actorUid: context.actorUid,
        draftCount: finishDrafts.length,
      });
      return;
    }

    const rankingDrafts = detectRankingEvents(context);
    const gapDrafts = detectGapEvents(context);
    const progressionDrafts = detectProgressionEvents(context);
    const streakDrafts = detectStreakEvents(context);
    const firstBloodDrafts = detectFirstBloodEvents(context);

    const drafts = await settleRaceFinish(context, [
      ...detectProgressEvents(context),
      ...rankingDrafts,
      ...gapDrafts,
      ...progressionDrafts,
      ...streakDrafts,
      ...firstBloodDrafts,
    ]);

    await persistEventDrafts(context.competitionId, drafts, batchId);

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

    // Large challenge: a newcomer is news to their followers and teammates,
    // not to 200 strangers.
    const recipients = audienceFor(
      await loadAudience(
        competitionRef,
        parseChallenge(competitionData),
        participantsSnap.docs.map((doc) => doc.data()),
        participantUid
      ),
      participantsSnap.docs
        .map((doc) => doc.data().uid as string | undefined)
        .filter((uid): uid is string => !!uid),
      participantUid,
      "social"
    );

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

    const recipients = audienceFor(
      await loadAudience(
        competitionRef,
        parseChallenge(competitionData),
        participantsSnap.docs.map((doc) => doc.data()),
        participantUid
      ),
      participantsSnap.docs
        .map((doc) => doc.data().uid as string | undefined)
        .filter((uid): uid is string => !!uid),
      participantUid,
      "social"
    );

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

    // A departing holder's badge passes on (silently — nobody took it).
    if (parseChallenge(competitionData).aggressor.uid === participantUid) {
      await settleAggressor(competitionId, "holderLeft", null);
    }
  },
);
