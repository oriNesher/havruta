import {randomUUID} from "crypto";
import * as admin from "firebase-admin";
import {EventDraft} from "./types";
import {isCelebrationType} from "./celebrationTypes";
import {
  buildProgressEventMetadata,
  isWithinProgressMergeWindow,
  ProgressEventMetadata,
} from "./rules/progress";

/**
 * Writes decided event drafts to competitions/{competitionId}/events.
 *
 * Every draft passed in one call came from the same trigger invocation (see
 * onParticipantProgressCreateEvents), so they all share one batchId — this
 * is what lets the client group, say, a "milestone" and a "tookTheLead"
 * fired by the same progress update into a single celebration screen
 * instead of showing them one after another.
 * @param {string} competitionId Competition the drafts belong to.
 * @param {EventDraft[]} drafts Drafts produced by the event rules.
 * @param {string} batchId Correlates drafts from the same trigger
 *   invocation; defaults to a fresh id when the caller doesn't need to
 *   share one across multiple persistEventDrafts calls.
 * @return {Promise<void>} Resolves once all writes complete.
 */
export async function persistEventDrafts(
  competitionId: string,
  drafts: EventDraft[],
  batchId: string = randomUUID()
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
          batchId,
          unseenByUserUids: draft.recipients,
          lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      if (draft.target.kind === "upsertProgress") {
        await upsertProgressEvent(eventsRef, competitionId, draft, batchId);
        return;
      }

      await eventsRef.add({
        type: draft.type,
        status: "open",
        competitionId,
        batchId,
        ...(isCelebrationType(draft.type) ? {actorCelebrated: false} : {}),
        unseenByUserUids: draft.recipients,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...draft.payload,
      });
    })
  );
}

interface ProgressCursorData {
  eventId: string;
  lastUpdatedAt: FirebaseFirestore.Timestamp;
  metadata: ProgressEventMetadata;
}

/**
 * Merges a progress update into the actor's still-fresh progress event, or
 * creates a new one, inside a transaction. The merge decision is driven by
 * a small per-actor "cursor" doc (competitions/{id}/progressCursors/{uid})
 * rather than a query against the events collection or the event doc
 * itself, for two reasons:
 *
 * - Race safety: deciding create-vs-merge from a query or a stale read
 *   outside the transaction is exactly what let concurrent rapid-fire
 *   updates (e.g. the "log progress" button mashed repeatedly) each see
 *   "nothing to merge into" and each create their own duplicate instead of
 *   merging. A transactional read of one specific document (even one that
 *   doesn't exist yet) is something Firestore reliably detects conflicts
 *   on; a query that currently matches nothing is not, since there's no
 *   document for a concurrent transaction's write to collide with. Keying
 *   the cursor doc's id on the actor makes this a document read, so
 *   concurrent upserts for the same actor serialize correctly instead of
 *   racing.
 * - History: unlike the event doc itself, the cursor is safe to overwrite
 *   every update (including across session boundaries) because it isn't
 *   user-visible — the actual event doc gets a fresh id each new session
 *   (once the merge window in isWithinProgressMergeWindow has lapsed since
 *   the cursor's last update), so a past session's card is preserved
 *   instead of being overwritten by the next one.
 *
 * The cursor carries its own copy of the current event's metadata so the
 * transaction never needs to read the event doc — only the cursor doc
 * participates in conflict detection, keeping unrelated actors' updates
 * from contending with each other.
 * @param {FirebaseFirestore.CollectionReference} eventsRef The competition's
 *   events collection.
 * @param {string} competitionId Competition the event belongs to.
 * @param {EventDraft} draft The upsertProgress draft to apply.
 * @param {string} batchId Correlates this write with any other events
 *   created by the same trigger invocation.
 * @return {Promise<void>} Resolves once the merge or create completes.
 */
async function upsertProgressEvent(
  eventsRef: FirebaseFirestore.CollectionReference,
  competitionId: string,
  draft: EventDraft,
  batchId: string
): Promise<void> {
  const payload = draft.payload as {
    competitionTitle: string;
    actorUid: string;
    actorUsername: string;
    beforeProgress: number;
    afterProgress: number;
  };

  const cursorRef = admin
    .firestore()
    .collection("competitions")
    .doc(competitionId)
    .collection("progressCursors")
    .doc(payload.actorUid);

  await admin.firestore().runTransaction(async (transaction) => {
    const cursorSnap = await transaction.get(cursorRef);
    const cursorData = cursorSnap.data() as ProgressCursorData | undefined;
    const now = admin.firestore.Timestamp.now();

    const canMerge =
      !!cursorData &&
      isWithinProgressMergeWindow(cursorData.lastUpdatedAt, now);

    const metadata = buildProgressEventMetadata(
      canMerge ? cursorData?.metadata : undefined,
      payload.beforeProgress,
      payload.afterProgress
    );

    const eventRef = canMerge && cursorData ?
      eventsRef.doc(cursorData.eventId) :
      eventsRef.doc();

    const fields = {
      type: "progress",
      competitionId,
      batchId,
      // Reset (not just set-once) on every merge: "progress" is
      // celebration-eligible, and each merge represents fresh progress the
      // actor just logged, so a prior celebration of this same doc shouldn't
      // suppress celebrating the new activity folded into it.
      actorCelebrated: false,
      unseenByUserUids: draft.recipients,
      lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      competitionTitle: payload.competitionTitle,
      actorUid: payload.actorUid,
      actorUsername: payload.actorUsername,
      targetUid: null,
      targetUsername: null,
      metadata,
    };

    if (canMerge) {
      transaction.update(eventRef, fields);
    } else {
      transaction.set(eventRef, {
        ...fields,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    transaction.set(cursorRef, {
      eventId: eventRef.id,
      lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      metadata,
    });
  });
}
