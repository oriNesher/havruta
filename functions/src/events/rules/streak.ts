import {EventDraft, EventsContext} from "../types";

const STREAK_MILESTONES = [3, 7, 14, 30, 60, 100];

/**
 * Creates an "activityStreak" event when today's update lands on a new
 * active day (computed in context.ts) whose resulting streak count is
 * exactly one of the milestone values.
 * @param {EventsContext} context Shared context for this participant update.
 * @return {EventDraft[]} The streak event draft to persist, if any.
 */
export function detectStreakEvents(context: EventsContext): EventDraft[] {
  const {
    competitionTitle,
    actorUid,
    actorUsername,
    participantUids,
    isNewActiveDay,
    newStreakCount,
  } = context;

  if (!isNewActiveDay || !STREAK_MILESTONES.includes(newStreakCount)) {
    return [];
  }

  const recipients = participantUids.filter((uid) => uid !== actorUid);

  return [
    {
      type: "activityStreak",
      recipients,
      target: {kind: "create"},
      payload: {
        competitionTitle,
        actorUid,
        actorUsername,
        targetUid: null,
        targetUsername: null,
        metadata: {
          streak: newStreakCount,
        },
      },
    },
  ];
}
