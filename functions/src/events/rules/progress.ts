import {EventDraft, EventsContext} from "../types";

/**
 * Creates a "progress" event, or merges into the actor's still-open one
 * instead of creating a duplicate.
 * @param {EventsContext} context Shared context for this participant update.
 * @return {EventDraft[]} The progress event draft to persist.
 */
export function detectProgressEvents(context: EventsContext): EventDraft[] {
  const {
    competitionTitle,
    actorUid,
    actorUsername,
    beforeProgress,
    afterProgress,
    participantUids,
    existingOpenProgressEvent,
  } = context;

  const recipients = participantUids.filter((uid) => uid !== actorUid);

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
