import {EventDraft, EventsContext} from "../types";

const INACTIVITY_THRESHOLD_DAYS = 7;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

// How long a progress event keeps absorbing the same actor's further
// updates after its last write. A sliding window, not a fixed session
// length: every new update resets the clock. Deliberately short — this
// exists only to merge a rapid-fire burst of "log progress" taps into one
// event, not to bucket a whole sitting. Any other event type firing in
// between (a rank change, a streak, etc.) no longer breaks the merge; only
// this actor going quiet for the full window does.
export const PROGRESS_MERGE_WINDOW_MS = 30 * 1000;

export interface ProgressEventMetadata {
  beforeProgress: number;
  afterProgress: number;
  progressDelta: number;
  updatesCount: number;
}

/**
 * Whether an existing progress event is still within its merge window,
 * i.e. its last update was recent enough that this update should fold into
 * it rather than start a fresh event.
 * @param {FirebaseFirestore.Timestamp | undefined} lastUpdatedAt The
 *   existing progress event's last-updated time, if one exists.
 * @param {FirebaseFirestore.Timestamp} now The current update's time.
 * @return {boolean} True if the update should merge into the existing event.
 */
export function isWithinProgressMergeWindow(
  lastUpdatedAt: FirebaseFirestore.Timestamp | undefined,
  now: FirebaseFirestore.Timestamp
): boolean {
  if (!lastUpdatedAt) return false;
  return now.toMillis() - lastUpdatedAt.toMillis() <= PROGRESS_MERGE_WINDOW_MS;
}

/**
 * Computes the metadata a progress event should have after folding in one
 * update. Pure so it can run inside a Firestore transaction and be
 * unit-tested without Firestore.
 *
 * Combines via min/max rather than "this update wins" so the result is
 * order-independent: Firestore doesn't guarantee trigger delivery order for
 * rapid successive writes to the same participant doc, so a burst of taps
 * can have its Cloud Function invocations processed out of order. Since
 * progress only ever increases, the true session start is the smallest
 * beforeProgress seen and the true current total is the largest
 * afterProgress seen, regardless of which invocation happened to commit
 * last.
 * @param {Partial<ProgressEventMetadata> | undefined} existingMetadata
 *   Metadata of the progress event this update folds into, if any, read
 *   transactionally at write time.
 * @param {number} beforeProgress This update's progress value beforehand.
 * @param {number} afterProgress This update's progress value after.
 * @return {ProgressEventMetadata} The metadata to write.
 */
export function buildProgressEventMetadata(
  existingMetadata: Partial<ProgressEventMetadata> | undefined,
  beforeProgress: number,
  afterProgress: number
): ProgressEventMetadata {
  const existingBefore = existingMetadata?.beforeProgress;
  const originalBeforeProgress = existingBefore === undefined ?
    beforeProgress :
    Math.min(existingBefore, beforeProgress);

  const existingAfter = existingMetadata?.afterProgress;
  const latestAfterProgress = existingAfter === undefined ?
    afterProgress :
    Math.max(existingAfter, afterProgress);
  const previousUpdatesCount = existingMetadata?.updatesCount ?? 0;

  return {
    beforeProgress: originalBeforeProgress,
    afterProgress: latestAfterProgress,
    progressDelta: latestAfterProgress - originalBeforeProgress,
    updatesCount: previousUpdatesCount + 1,
  };
}

/**
 * Creates a "backInRace" event when the actor returns from a meaningful
 * inactivity gap, or a "progress" upsert draft that persist.ts will
 * transactionally merge into the actor's progress event if it's still
 * within its merge window (or create fresh) — that decision can't be made
 * here, since it has to happen atomically with the write.
 * @param {EventsContext} context Shared context for this participant update.
 * @return {EventDraft[]} The event draft to persist.
 */
export function detectProgressEvents(context: EventsContext): EventDraft[] {
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
      },
    },
  ];
}
