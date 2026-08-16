import * as admin from "firebase-admin";

export interface InviteLookupResult {
  valid: boolean;
  reason?: "not_found" | "revoked" | "expired" | "full";
  linkId?: string;
  competitionId?: string;
  competitionTitle?: string;
  competitionType?: string;
  createdBy?: string;
  createdByUsername?: string;
  sharedGoalTitle?: string;
  sharedTargetValue?: number;
  sharedUnit?: string;
  creatorGoalTitle?: string;
  creatorTargetValue?: number;
  creatorUnit?: string;
}

/**
 * Looks up a challenge_invite_links/{linkId} doc and validates it (exists,
 * not revoked, not expired, not over capacity). Shared by the getInvite
 * callable and the (future) web landing page handler so both surfaces
 * enforce the same rules from one place.
 * @param {string} linkId The invite link's document id (the token itself).
 * @return {Promise<InviteLookupResult>} The validated preview, or a reason.
 */
export async function lookupInvite(
  linkId: string
): Promise<InviteLookupResult> {
  const db = admin.firestore();
  const snap = await db.collection("challenge_invite_links").doc(linkId).get();

  if (!snap.exists) {
    return {valid: false, reason: "not_found"};
  }

  const data = snap.data() || {};

  if (data.revoked === true) {
    return {valid: false, reason: "revoked"};
  }

  const expiresAt = data.expiresAt as admin.firestore.Timestamp | undefined;
  if (expiresAt && expiresAt.toMillis() < Date.now()) {
    return {valid: false, reason: "expired"};
  }

  const maxRedemptions = data.maxRedemptions as number | null | undefined;
  const redemptionCount = (data.redemptionCount as number | undefined) ?? 0;
  if (
    typeof maxRedemptions === "number" &&
    redemptionCount >= maxRedemptions
  ) {
    return {valid: false, reason: "full"};
  }

  return {
    valid: true,
    linkId,
    competitionId: data.competitionId,
    competitionTitle: data.competitionTitle,
    competitionType: data.competitionType,
    createdBy: data.createdBy,
    createdByUsername: data.createdByUsername,
    sharedGoalTitle: data.sharedGoalTitle,
    sharedTargetValue: data.sharedTargetValue,
    sharedUnit: data.sharedUnit,
    creatorGoalTitle: data.creatorGoalTitle,
    creatorTargetValue: data.creatorTargetValue,
    creatorUnit: data.creatorUnit,
  };
}
