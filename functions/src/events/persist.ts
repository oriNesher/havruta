import * as admin from "firebase-admin";
import {EventDraft, EventsContext} from "./types";
import {
  buildProgressEventUpdate,
  ProgressEventMetadata,
} from "./rules/progress";

/**
 * Writes decided event drafts to competitions/{competitionId}/events, then
 * closes any open progress event this batch didn't explicitly touch. A
 * progress event only stays open across calls when the same actor's next
 * progress update explicitly merges into it (an "update" draft targeting
 * that doc); any other write to the competition's events — another actor's
 * event, a join/leave, a backInRace — means something happened since, so it
 * no longer represents an uninterrupted run and gets closed.
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

  // Doc ids to exempt from the stale-progress sweep below: explicit merges
  // into an existing progress doc, plus whichever progress doc this batch's
  // upsert (below) ends up touching.
  const exemptDocIds = new Set(
    drafts
      .filter((draft) => draft.target.kind === "update")
      .map((draft) => (draft.target as {docId: string}).docId)
  );

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

      if (draft.target.kind === "upsertProgress") {
        const docId =
          await upsertProgressEvent(eventsRef, competitionId, draft);
        exemptDocIds.add(docId);
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

  await closeStaleOpenProgressEvents(eventsRef, exemptDocIds);
}

/**
 * Merges a progress update into the actor's still-open progress event, or
 * creates a fresh one, inside a transaction. The existing-open-event read
 * has to happen here rather than earlier in context.ts: reading it ahead of
 * time and deciding create-vs-merge from that stale snapshot is exactly what
 * let concurrent rapid-fire updates (e.g. the "log progress" button mashed
 * repeatedly) each see "no open event" and each create their own duplicate
 * instead of merging. Firestore aborts and retries a transaction whose query
 * results changed before commit, so concurrent upserts for the same actor
 * serialize correctly instead of racing.
 * @param {FirebaseFirestore.CollectionReference} eventsRef The competition's
 *   events collection.
 * @param {string} competitionId Competition the event belongs to.
 * @param {EventDraft} draft The upsertProgress draft to apply.
 * @return {Promise<string>} The id of the progress event doc that was
 *   merged into or created.
 */
async function upsertProgressEvent(
  eventsRef: FirebaseFirestore.CollectionReference,
  competitionId: string,
  draft: EventDraft
): Promise<string> {
  const payload = draft.payload as {
    competitionTitle: string;
    actorUid: string;
    actorUsername: string;
    beforeProgress: number;
    afterProgress: number;
    hasSeparatingEvent: boolean;
  };

  return admin.firestore().runTransaction(async (transaction) => {
    const openSnap = await transaction.get(
      eventsRef
        .where("type", "==", "progress")
        .where("actorUid", "==", payload.actorUid)
        .where("status", "==", "open")
        .limit(1)
    );

    const existingDoc = openSnap.empty ? null : openSnap.docs[0];
    const existingMetadata = existingDoc?.data().metadata as
      | Partial<ProgressEventMetadata>
      | undefined;

    const {status, metadata} = buildProgressEventUpdate(
      existingMetadata,
      payload.beforeProgress,
      payload.afterProgress,
      payload.hasSeparatingEvent
    );

    if (existingDoc) {
      transaction.update(existingDoc.ref, {
        competitionTitle: payload.competitionTitle,
        actorUsername: payload.actorUsername,
        status,
        metadata,
        unseenByUserUids: draft.recipients,
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return existingDoc.id;
    }

    const newRef = eventsRef.doc();
    transaction.set(newRef, {
      type: "progress",
      status,
      competitionId,
      unseenByUserUids: draft.recipients,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      competitionTitle: payload.competitionTitle,
      actorUid: payload.actorUid,
      actorUsername: payload.actorUsername,
      targetUid: null,
      targetUsername: null,
      metadata,
    });
    return newRef.id;
  });
}

/**
 * Closes every open progress event not named in exemptDocIds — i.e. every
 * progress event that still exists only because nothing has touched it,
 * not because this batch just merged into or created it.
 * @param {FirebaseFirestore.CollectionReference} eventsRef The competition's
 *   events collection.
 * @param {Set<string>} exemptDocIds Doc ids this batch just merged into or
 *   freshly created — left untouched.
 * @return {Promise<void>} Resolves once all closes complete.
 */
async function closeStaleOpenProgressEvents(
  eventsRef: FirebaseFirestore.CollectionReference,
  exemptDocIds: Set<string>
): Promise<void> {
  const openProgressSnap = await eventsRef
    .where("type", "==", "progress")
    .where("status", "==", "open")
    .get();

  const staleDocs = openProgressSnap.docs.filter(
    (doc) => !exemptDocIds.has(doc.id)
  );

  if (staleDocs.length === 0) return;

  await Promise.all(
    staleDocs.map((doc) =>
      doc.ref.update({
        status: "closed",
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      })
    )
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
