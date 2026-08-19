import {EventDraft, EventsContext} from "../types";

const INACTIVITY_THRESHOLD_DAYS = 7;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

export interface ProgressEventMetadata {
  beforeProgress: number;
  afterProgress: number;
  progressDelta: number;
  updatesCount: number;
}

export interface ProgressEventUpdate {
  status: "open" | "closed";
  metadata: ProgressEventMetadata;
}

/**
 * Computes the status/metadata a progress event should have after folding
 * in one update. Pure so it can run inside a Firestore transaction (the
 * actual existing-open-event read has to happen there, not earlier, or
 * concurrent updates from the same actor race each other into duplicate
 * events instead of merging) and be unit-tested without Firestore.
 * @param {Partial<ProgressEventMetadata> | undefined} existingMetadata
 *   Metadata of the still-open progress event this update folds into, if
 *   any, read transactionally at write time.
 * @param {number} beforeProgress This update's progress value beforehand.
 * @param {number} afterProgress This update's progress value after.
 * @param {boolean} hasSeparatingEvent Whether another event type also fired
 *   for this same update, or something else already closed the previous
 *   chain — either way the resulting event should not stay open for the
 *   next update to silently absorb.
 * @return {ProgressEventUpdate} The status and metadata to write.
 */
export function buildProgressEventUpdate(
  existingMetadata: Partial<ProgressEventMetadata> | undefined,
  beforeProgress: number,
  afterProgress: number,
  hasSeparatingEvent: boolean
): ProgressEventUpdate {
  const originalBeforeProgress =
    existingMetadata?.beforeProgress ?? beforeProgress;
  const previousUpdatesCount = existingMetadata?.updatesCount ?? 0;

  return {
    status: hasSeparatingEvent ? "closed" : "open",
    metadata: {
      beforeProgress: originalBeforeProgress,
      afterProgress,
      progressDelta: afterProgress - originalBeforeProgress,
      updatesCount: previousUpdatesCount + 1,
    },
  };
}

/**
 * Creates a "backInRace" event when the actor returns from a meaningful
 * inactivity gap, or a "progress" upsert draft that persist.ts will
 * transactionally merge into the actor's still-open progress event (or
 * create fresh) — that decision can't be made here, since the "is there
 * still an open one" read has to happen atomically with the write.
 * @param {EventsContext} context Shared context for this participant update.
 * @param {boolean} hasSeparatingEvent Whether this same update also produced
 *   a non-progress event for this actor.
 * @return {EventDraft[]} The event draft to persist.
 */
export function detectProgressEvents(
  context: EventsContext,
  hasSeparatingEvent: boolean
): EventDraft[] {
  const {
    competitionTitle,
    actorUid,
    actorUsername,
    beforeProgress,
    afterProgress,
    participantUids,
    previousUpdatedAt,
    currentUpdatedAt,
  } = context;

  const recipients = participantUids.filter((uid) => uid !== actorUid);

  // Progress only ever increases (decreases already exit earlier), so a
  // beforeProgress of 0 reliably means this is the actor's first-ever
  // contribution.
  const isFirstEverUpdate = beforeProgress === 0;

  const inactivityDays = previousUpdatedAt && currentUpdatedAt ?
    (currentUpdatedAt.toMillis() - previousUpdatedAt.toMillis()) / MS_PER_DAY :
    0;

  const isBackInRace =
    !isFirstEverUpdate && inactivityDays >= INACTIVITY_THRESHOLD_DAYS;

  if (isBackInRace) {
    return [
      {
        type: "backInRace",
        recipients,
        target: {kind: "create"},
        payload: {
          competitionTitle,
          actorUid,
          actorUsername,
          targetUid: null,
          targetUsername: null,
          metadata: {
            beforeProgress,
            afterProgress,
            progressDelta: afterProgress - beforeProgress,
            inactivityDays,
          },
        },
      },
    ];
  }

  return [
    {
      type: "progress",
      recipients,
      target: {kind: "upsertProgress"},
      payload: {
        competitionTitle,
        actorUid,
        actorUsername,
        targetUid: null,
        targetUsername: null,
        beforeProgress,
        afterProgress,
        hasSeparatingEvent,
      },
    },
  ];
}
