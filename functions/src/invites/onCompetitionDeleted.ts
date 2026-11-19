import {onDocumentDeleted} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

// Deleting the challenge doc is the only client step of deleting a
// challenge; everything hanging off it is cleaned up here, server-side,
// because firestore.rules gives clients no delete access to any of it:
// - its subcollections (participants, events, progress cursors, …) — no
//   client may delete another participant's doc, and a deleted parent
//   can't vouch for the deleter anyway;
// - its direct invites (competition_invites), so none stays acceptable;
// - its invite links and their redemptions — a bearer credential kept
//   entirely server-side, so a leftover link can't keep resolving.
// (The export keeps its original name: renaming a deployed function
// deletes and recreates it.)
// Safe to re-run if the trigger is retried: already-deleted docs simply
// aren't found again. Participant deletions fired from here are skipped
// by onParticipantLeaveCreateEvents, which sees the parent is gone.
export const onCompetitionDeletedCleanupInviteLinks = onDocumentDeleted(
  {
    document: "competitions/{competitionId}",
    maxInstances: 5,
    timeoutSeconds: 300,
  },
  async (event) => {
    const competitionId = event.params.competitionId;
    const db = admin.firestore();

    const [linksSnap, invitesSnap] = await Promise.all([
      db.collection("challenge_invite_links")
        .where("competitionId", "==", competitionId)
        .get(),
      db.collection("competition_invites")
        .where("competitionId", "==", competitionId)
        .get(),
    ]);

    await Promise.all([
      db.recursiveDelete(db.collection("competitions").doc(competitionId)),
      ...linksSnap.docs.map((doc) => db.recursiveDelete(doc.ref)),
      ...invitesSnap.docs.map((doc) => doc.ref.delete()),
    ]);

    logger.info("Cleaned up deleted challenge", {
      competitionId,
      linkCount: linksSnap.size,
      inviteCount: invitesSnap.size,
    });
  }
);
