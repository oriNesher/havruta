import {onCall} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {toStandingParticipant} from "../challenges/standings";
import {asCallable, loadAsOrganizer, requireCaller, writeAudit} from "./access";
import {planSettingsChange, SettingsPatch} from "./settings";

interface UpdateChallengeSettingsRequest extends SettingsPatch {
  competitionId: string;
}

/**
 * Organizer edit of a challenge after launch: title, description, start,
 * end, daily minimum, race target (see planSettingsChange for what's
 * allowed when). Applied and audited in one transaction; a new race target
 * is also copied onto every participant doc, which standings read first.
 * Afterwards the invite previews (links and pending direct invites) are
 * refreshed so joiners see the current rules.
 */
export const updateChallengeSettings =
  onCall<UpdateChallengeSettingsRequest>({maxInstances: 5}, (request) =>
    asCallable(async () => {
      const {uid, competitionId} = requireCaller(request);
      const patch = request.data;
      const db = admin.firestore();

      const plan = await db.runTransaction(async (tx) => {
        const ctx = await loadAsOrganizer(tx, competitionId, uid);
        const participantsSnap = patch.targetValue !== undefined ?
          await tx.get(ctx.ref.collection("participants")) :
          null;
        const participants = (participantsSnap?.docs ?? [])
          .map((doc) => toStandingParticipant(doc.data(), ctx.challenge))
          .filter((p) => !!p.uid);

        const plan = planSettingsChange(
          ctx.challenge,
          {
            title: typeof ctx.data.title === "string" ? ctx.data.title : "",
            description: typeof ctx.data.description === "string" ?
              ctx.data.description :
              "",
          },
          participants,
          {
            title: patch.title,
            description: patch.description,
            startsAtMillis: patch.startsAtMillis,
            endsAtMillis: patch.endsAtMillis,
            dailyMinimum: patch.dailyMinimum,
            targetValue: patch.targetValue,
          },
          Date.now()
        );

        const update: Record<string, unknown> = {};
        if (plan.title !== undefined) update.title = plan.title;
        if (plan.description !== undefined) {
          update.description = plan.description;
        }
        if (plan.startsAtMillis !== undefined) {
          update.startsAt =
            admin.firestore.Timestamp.fromMillis(plan.startsAtMillis);
        }
        if (plan.endsAtMillis !== undefined) {
          const endsAt = plan.endsAtMillis;
          update.endsAt = endsAt === null ?
            admin.firestore.FieldValue.delete() :
            admin.firestore.Timestamp.fromMillis(endsAt);
          // Legacy display field older builds' "Nd left" chip parses.
          update.deadline = endsAt === null ?
            admin.firestore.FieldValue.delete() :
            new Date(endsAt).toISOString().slice(0, 10);
        }
        if (plan.dailyMinimum !== undefined) {
          update["rules.dailyMinimum"] = plan.dailyMinimum;
        }
        if (plan.targetValue !== undefined) {
          update.sharedTargetValue = plan.targetValue;
          for (const doc of participantsSnap?.docs ?? []) {
            tx.update(doc.ref, {targetValue: plan.targetValue});
          }
        }

        tx.update(ctx.ref, update);
        writeAudit(tx, ctx, {
          action: "updateSettings",
          before: Object.fromEntries(Object.entries(plan.changes)
            .map(([field, change]) => [field, change.before])),
          after: Object.fromEntries(Object.entries(plan.changes)
            .map(([field, change]) => [field, change.after])),
        });
        return plan;
      });

      await refreshInvitePreviews(competitionId, plan);
      logger.info("Challenge settings updated", {
        competitionId,
        uid,
        fields: Object.keys(plan.changes),
      });
      return {changed: Object.keys(plan.changes)};
    })
  );

/**
 * Brings the copies of the challenge's definition that invites carry up to
 * date, so a joiner never sees stale rules. Best effort: joining itself
 * always reads the live challenge.
 * @param {string} competitionId The challenge.
 * @param {object} plan What changed.
 * @param {string} [plan.title] New title.
 * @param {number} [plan.dailyMinimum] New daily minimum.
 * @param {number} [plan.targetValue] New race target.
 */
async function refreshInvitePreviews(
  competitionId: string,
  plan: {title?: string; dailyMinimum?: number; targetValue?: number}
): Promise<void> {
  const linkFields: Record<string, unknown> = {};
  const inviteFields: Record<string, unknown> = {};
  if (plan.title !== undefined) {
    linkFields.competitionTitle = plan.title;
    inviteFields.competitionTitle = plan.title;
  }
  if (plan.dailyMinimum !== undefined) {
    linkFields.dailyMinimum = plan.dailyMinimum;
    inviteFields["rules.dailyMinimum"] = plan.dailyMinimum;
  }
  if (plan.targetValue !== undefined) {
    linkFields.sharedTargetValue = plan.targetValue;
    inviteFields.sharedTargetValue = plan.targetValue;
  }
  if (Object.keys(linkFields).length === 0) return;

  const db = admin.firestore();
  try {
    const [links, invites] = await Promise.all([
      db.collection("challenge_invite_links")
        .where("competitionId", "==", competitionId)
        .where("revoked", "==", false)
        .get(),
      db.collection("competition_invites")
        .where("competitionId", "==", competitionId)
        .where("status", "==", "pending")
        .get(),
    ]);
    const writer = db.bulkWriter();
    links.docs.forEach((doc) => writer.update(doc.ref, linkFields));
    invites.docs.forEach((doc) => writer.update(doc.ref, inviteFields));
    await writer.close();
  } catch (error) {
    logger.error("Refreshing invite previews failed", {competitionId, error});
  }
}
