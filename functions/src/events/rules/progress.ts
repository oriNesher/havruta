import {EventDraft, EventsContext} from "../types";

const INACTIVITY_THRESHOLD_DAYS = 7;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * Creates a "backInRace" event when the actor returns from a meaningful
 * inactivity gap, a "progress" event, or merges into the actor's still-open
 * progress event instead of creating a duplicate. Whenever another event
 * type also fired for this same update (a milestone, overtook, etc.), the
 * resulting progress event is closed immediately so the next plain progress
 * update starts a fresh one instead of silently absorbing it.
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
    existingOpenProgressEvent,
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

  if (existingOpenProgressEvent) {
    const existingMetadata = existingOpenProgressEvent.data.metadata ?? {};
    const originalBeforeProgress =
      existingMetadata.beforeProgress ?? beforeProgress;
    const previousUpdatesCount = existingMetadata.updatesCount ?? 1;

    return [
      {
        type: "progress",
        recipients,
        target: {kind: "update", docId: existingOpenProgressEvent.id},
        payload: {
          competitionTitle,
          actorUsername,
          status: hasSeparatingEvent ? "closed" : "open",
          metadata: {
            beforeProgress: originalBeforeProgress,
            afterProgress,
            progressDelta: afterProgress - originalBeforeProgress,
            updatesCount: previousUpdatesCount + 1,
          },
        },
      },
    ];
  }

  return [
    {
      type: "progress",
      recipients,
      target: {kind: "create"},
      payload: {
        competitionTitle,
        actorUid,
        actorUsername,
        targetUid: null,
        targetUsername: null,
        status: hasSeparatingEvent ? "closed" : "open",
        metadata: {
          beforeProgress,
          afterProgress,
          progressDelta: afterProgress - beforeProgress,
          updatesCount: 1,
        },
      },
    },
  ];
}
