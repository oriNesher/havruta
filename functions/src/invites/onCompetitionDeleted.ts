import {onDocumentDeleted} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

// Invite links are a bearer credential that firestore.rules keeps entirely
// server-side (no client read or write), so the client's deleteCompetition
// can't clean them up itself. Deleting the challenge doc is the signal:
// every link for it — and each link's redemptions subcollection — goes
// here, so a leftover link can't keep resolving to a deleted challenge.
export const onCompetitionDeletedCleanupInviteLinks = onDocumentDeleted(
  {
    document: "competitions/{competitionId}",
    maxInstances: 5,
  },
  async (event) => {
    const competitionId = event.params.competitionId;
    const db = admin.firestore();

    const linksSnap = await db
      .collection("challenge_invite_links")
      .where("competitionId", "==", competitionId)
      .get();

    // recursiveDelete also removes redemptions/{uid}. Safe to re-run if the
    // trigger is retried: already-deleted links simply aren't found again.
    await Promise.all(
      linksSnap.docs.map((doc) => db.recursiveDelete(doc.ref))
    );

    logger.info("Invite links cleaned up for deleted challenge", {
      competitionId,
      linkCount: linksSnap.size,
    });
  }
);
