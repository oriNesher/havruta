import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {buildInviteUrl} from "./config";
import {parseChallenge} from "../challenges/model";
import {
  joinClosedReason,
  joinClosesAtMillis,
} from "../challenges/joining";

interface CreateInviteRequest {
  competitionId: string;
}

// competition.deadline is a free-text field ("30 days" / "By August 1st"),
// not a parseable date, so link expiry can't be derived from it — use a
// fixed window instead.
const DEFAULT_EXPIRY_DAYS = 30;

// The user is staring at a spinner on the Share button until this
// returns, so a cold start here is felt directly — but a reserved warm
// instance bills around the clock, so the batched reads below carry the
// latency work instead and the cold start is accepted for now.
export const createInvite = onCall<CreateInviteRequest>(
  {maxInstances: 5},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const competitionId = request.data?.competitionId;
    if (!competitionId || typeof competitionId !== "string") {
      throw new HttpsError("invalid-argument", "competitionId is required.");
    }

    const db = admin.firestore();
    const competitionRef = db.collection("competitions").doc(competitionId);

    // The permission check needs the competition doc and the reuse check
    // needs the existing-links query, but neither depends on the other —
    // issuing them together saves a round trip on the path the user is
    // waiting on. The permission check is still applied before anything is
    // read out of the query's result or written.
    //
    // Reuse an existing active link rather than minting a new one on every
    // tap of "Share" — avoids link proliferation for the same challenge.
    const [competitionSnap, existingSnap] = await Promise.all([
      competitionRef.get(),
      db
        .collection("challenge_invite_links")
        .where("competitionId", "==", competitionId)
        .where("createdBy", "==", uid)
        .where("revoked", "==", false)
        .limit(5)
        .get(),
    ]);

    if (!competitionSnap.exists) {
      throw new HttpsError("not-found", "Challenge not found.");
    }

    const competitionData = competitionSnap.data() || {};
    const participantUids = (competitionData.participantUids as string[]) ?? [];

    if (!participantUids.includes(uid)) {
      throw new HttpsError(
        "permission-denied",
        "Only participants can create an invite link for this challenge."
      );
    }

    const now = Date.now();
    const challenge = parseChallenge(competitionData);
    const closedReason = joinClosedReason(challenge, now);
    if (closedReason) {
      throw new HttpsError("failed-precondition", closedReason);
    }
    const stillValid = existingSnap.docs.find((doc) => {
      const expiresAt = doc.data().expiresAt as
        | admin.firestore.Timestamp
        | undefined;
      return !expiresAt || expiresAt.toMillis() > now;
    });

    if (stillValid) {
      logger.info("Reusing existing invite link", {
        competitionId,
        linkId: stillValid.id,
      });
      return {linkId: stillValid.id, url: buildInviteUrl(stillValid.id)};
    }

    // Older app builds branch on this, so it stays the legacy type name.
    const competitionType = challenge.isLegacyPersonal ?
      "personalGoalChallenge" :
      "sharedGoalChallenge";

    // A link never outlives the moment joining closes (the challenge's
    // end, or for Last One Standing the end of day 1).
    const expiresAt = admin.firestore.Timestamp.fromMillis(Math.min(
      now + DEFAULT_EXPIRY_DAYS * 24 * 60 * 60 * 1000,
      joinClosesAtMillis(challenge)
    ));

    // Legacy personal challenges store each participant's own goal on
    // their participants/{uid} subdoc, not on the competition doc itself —
    // read the creator's own goal there for the invite's "for reference"
    // preview. Fetched alongside the username rather than after it: both
    // are just display fields for the link, with no dependency between them.
    const [userSnap, creatorParticipantSnap] = await Promise.all([
      db.collection("users").doc(uid).get(),
      challenge.isLegacyPersonal ?
        competitionRef.collection("participants").doc(uid).get() :
        Promise.resolve(null),
    ]);

    const createdByUsername = userSnap.data()?.username ?? "Someone";

    let goalPreviewFields: Record<string, unknown> = {};
    if (!challenge.isLegacyPersonal) {
      goalPreviewFields = {
        winCondition: challenge.winCondition,
        sharedGoalTitle: challenge.goalTitle,
        sharedTargetValue: challenge.targetValue,
        sharedUnit: challenge.unit,
        dailyMinimum: challenge.rules.dailyMinimum,
      };
    } else {
      const creatorParticipantData = creatorParticipantSnap?.data() || {};
      goalPreviewFields = {
        creatorGoalTitle: creatorParticipantData.goalTitle ?? null,
        creatorTargetValue: creatorParticipantData.targetValue ?? null,
        creatorUnit: creatorParticipantData.unit ?? null,
      };
    }

    const linkRef = await db.collection("challenge_invite_links").add({
      competitionId,
      competitionTitle: competitionData.title ?? "",
      competitionType,
      createdBy: uid,
      createdByUsername,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt,
      revoked: false,
      revokedAt: null,
      maxRedemptions: null,
      redemptionCount: 0,
      ...goalPreviewFields,
    });

    logger.info("Created invite link", {competitionId, linkId: linkRef.id});

    return {linkId: linkRef.id, url: buildInviteUrl(linkRef.id)};
  }
);
