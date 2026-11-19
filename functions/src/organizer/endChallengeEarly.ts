import {onCall} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {toStandingParticipant} from "../challenges/standings";
import {persistEventDrafts} from "../events/persist";
import {loadAudienceFor} from "../events/loadAudience";
import {
  detectEliminationEvents,
  detectPlacementEvents,
} from "../events/rules/outcome";
import {asCallable, loadAsOrganizer, requireCaller, writeAudit} from "./access";
import {MAX_REASON} from "./correction";
import {planEarlyEnd} from "./endEarly";
import {OrganizerError} from "./errors";

interface EndChallengeEarlyRequest {
  competitionId: string;
  reason?: string;
}

/**
 * Organizer ends a running challenge now (see planEarlyEnd for how each
 * mode is decided). Completes it in one transaction — the same
 * status/winner fields the deadline and Last One Standing jobs write, plus
 * endsAt = now and endedEarly — then announces eliminations and winners
 * through the usual events, so winners get their celebration.
 */
export const endChallengeEarly = onCall<EndChallengeEarlyRequest>(
  {maxInstances: 5},
  (request) => asCallable(async () => {
    const {uid, competitionId} = requireCaller(request);
    const rawReason = request.data?.reason;
    const reason = typeof rawReason === "string" ? rawReason.trim() : "";
    if (reason.length > MAX_REASON) {
      throw new OrganizerError(
        `The reason can be at most ${MAX_REASON} characters.`);
    }

    const outcome = await admin.firestore().runTransaction(async (tx) => {
      const ctx = await loadAsOrganizer(tx, competitionId, uid);
      const participantsSnap = await tx.get(ctx.ref.collection("participants"));
      const participants = participantsSnap.docs
        .map((doc) => toStandingParticipant(doc.data(), ctx.challenge))
        .filter((p) => !!p.uid);

      const now = Date.now();
      const plan = planEarlyEnd(ctx.challenge, participants, now);
      const endsAt = admin.firestore.Timestamp.fromMillis(now);

      tx.update(ctx.ref, {
        ...plan.update,
        endsAt,
        deadline: new Date(now).toISOString().slice(0, 10),
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        endedEarly: {byUid: ctx.actorUid, at: endsAt},
      });
      for (const elimination of plan.eliminations) {
        tx.update(ctx.ref.collection("participants").doc(elimination.uid), {
          eliminatedOnDay: elimination.day,
          eliminatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      writeAudit(tx, ctx, {
        action: "endEarly",
        before: {status: "active"},
        after: {status: "completed", winnerUids: plan.winnerUids},
        reason: reason || null,
      });

      return {
        title: typeof ctx.data.title === "string" ?
          ctx.data.title :
          "Challenge",
        participants,
        plan,
      };
    });

    const {title, participants, plan} = outcome;
    const audience = await loadAudienceFor(
      admin.firestore().collection("competitions").doc(competitionId));
    await persistEventDrafts(competitionId, [
      ...detectEliminationEvents(
        title, participants, plan.eliminations, audience),
      ...detectPlacementEvents(
        title, participants, plan.placements, audience),
    ]);

    logger.info("Challenge ended early", {
      competitionId,
      uid,
      winnerUids: plan.winnerUids,
    });
    return {winnerUids: plan.winnerUids};
  })
);
