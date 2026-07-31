import * as admin from "firebase-admin";
import {EventDraft, EventsContext} from "./types";

/**
 * Writes decided event drafts to competitions/{competitionId}/events.
 * Contains no detection logic — rules decide what happens, this only
 * performs the create/update.
 * @param {string} competitionId Competition the drafts belong to.
 * @param {EventDraft[]} drafts Drafts produced by the event rules.
 * @return {Promise<void>} Resolves once all writes complete.
 */
export async function persistEventDrafts(
  competitionId: string,
  drafts: EventDraft[]
): Promise<void> {
  if (drafts.length === 0) return;

  const db = admin.firestore();
  const eventsRef = db
    .collection("competitions")
    .doc(competitionId)
    .collection("events");

  await Promise.all(
    drafts.map(async (draft) => {
      if (draft.target.kind === "update") {
        await eventsRef.doc(draft.target.docId).update({
          ...draft.payload,
          unseenByUserUids: draft.recipients,
          lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      await eventsRef.add({
        type: draft.type,
        status: "open",
        competitionId,
        unseenByUserUids: draft.recipients,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...draft.payload,
      });
    })
  );
}

/**
 * Writes the participant's updated streak state, computed in context.ts,
 * back onto their participant doc — only when today is a new active day.
 * @param {string} competitionId Competition the participant belongs to.
 * @param {string} participantId The participant doc's id.
 * @param {EventsContext} context Shared context for this participant update.
 * @return {Promise<void>} Resolves once the write completes.
 */
export async function persistParticipantStreak(
  competitionId: string,
  participantId: string,
  context: EventsContext
): Promise<void> {
  if (!context.isNewActiveDay) return;

  const db = admin.firestore();

  await db
    .collection("competitions")
    .doc(competitionId)
    .collection("participants")
    .doc(participantId)
    .update({
      currentStreak: context.newStreakCount,
      lastActiveDate: context.todayDateStr,
    });
}
