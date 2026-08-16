import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {buildInviteUrl} from "./config";

interface CreateInviteRequest {
  competitionId: string;
}

// competition.deadline is a free-text field ("30 days" / "By August 1st"),
// not a parseable date, so link expiry can't be derived from it — use a
// fixed window instead.
const DEFAULT_EXPIRY_DAYS = 30;

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
    const competitionSnap = await competitionRef.get();

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

    // Reuse an existing active link rather than minting a new one on every
    // tap of "Share" — avoids link proliferation for the same challenge.
    const existingSnap = await db
      .collection("challenge_invite_links")
      .where("competitionId", "==", competitionId)
      .where("createdBy", "==", uid)
      .where("revoked", "==", false)
      .limit(5)
      .get();

    const now = Date.now();
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

    const userSnap = await db.collection("users").doc(uid).get();
    const createdByUsername = userSnap.data()?.username ?? "Someone";

    const competitionType =
      (competitionData.type as string) ?? "personalGoalChallenge";

    const expiresAt = admin.firestore.Timestamp.fromMillis(
      now + DEFAULT_EXPIRY_DAYS * 24 * 60 * 60 * 1000
    );

    // personalGoalChallenge stores each participant's own goal on their
    // participants/{uid} subdoc, not on the competition doc itself — read
    // the creator's own goal there for the invite's "for reference" preview.
    let goalPreviewFields: Record<string, unknown> = {};
    if (competitionType === "sharedGoalChallenge") {
      goalPreviewFields = {
        sharedGoalTitle: competitionData.sharedGoalTitle ?? null,
        sharedTargetValue: competitionData.sharedTargetValue ?? null,
        sharedUnit: competitionData.sharedUnit ?? null,
      };
    } else {
      const creatorParticipantSnap = await competitionRef
        .collection("participants")
        .doc(uid)
        .get();
      const creatorParticipantData = creatorParticipantSnap.data() || {};
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
