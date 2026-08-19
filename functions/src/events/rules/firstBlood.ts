import {EventDraft, EventsContext} from "../types";

/**
 * Creates a "firstBlood" event the first time anyone logs progress in this
 * competition: the actor's own first-ever contribution (beforeProgress ===
 * 0) while every other participant is still at 0. Guarded by
 * hasFirstBloodEvent so a competition only ever awards it once, even if a
 * participant later drops back to 0 progress and logs again.
 * @param {EventsContext} context Shared context for this participant update.
 * @return {EventDraft[]} The firstBlood event draft to persist, if any.
 */
export function detectFirstBloodEvents(context: EventsContext): EventDraft[] {
  const {
    competitionTitle,
    actorUid,
    actorUsername,
    beforeProgress,
    participants,
    participantUids,
    hasFirstBloodEvent,
  } = context;

  const isFirstEverUpdate = beforeProgress === 0;

  if (!isFirstEverUpdate || hasFirstBloodEvent) {
    return [];
  }

  const someoneElseAlreadyLogged = participants.some(
    (participant) =>
      participant.uid !== actorUid && (participant.progress ?? 0) > 0
  );

  if (someoneElseAlreadyLogged) {
    return [];
  }

  const recipients = participantUids.filter((uid) => uid !== actorUid);

  return [
    {
      type: "firstBlood",
      recipients,
      target: {kind: "create"},
      payload: {
        competitionTitle,
        actorUid,
        actorUsername,
        targetUid: null,
        targetUsername: null,
        metadata: {},
      },
    },
  ];
}
