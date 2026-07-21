import {EventDraft, EventsContext} from "../types";

/**
 * Creates one "overtook" event per participant the actor just passed.
 * @param {EventsContext} context Shared context for this participant update.
 * @return {EventDraft[]} One draft per overtaken participant.
 */
export function detectRankingEvents(context: EventsContext): EventDraft[] {
  const {
    competitionTitle,
    actorUid,
    actorUsername,
    actorTargetValue,
    beforeProgress,
    afterProgress,
    participants,
  } = context;

  if (typeof actorTargetValue !== "number" || actorTargetValue <= 0) {
    return [];
  }

  const actorPercentBefore = beforeProgress / actorTargetValue;
  const actorPercentAfter = afterProgress / actorTargetValue;

  const drafts: EventDraft[] = [];

  for (const participant of participants) {
    const otherUid = participant.uid;

    if (!otherUid || otherUid === actorUid) {
      continue;
    }

    const otherUsername = participant.username ?? "Someone";
    const otherProgress = participant.progress ?? 0;
    const otherTargetValue = participant.targetValue ?? 0;

    if (typeof otherTargetValue !== "number" || otherTargetValue <= 0) {
      continue;
    }

    const otherPercent = otherProgress / otherTargetValue;

    // Overtook only if the actor was not ahead before and is ahead now.
    const overtookThisParticipant =
      actorPercentBefore <= otherPercent && actorPercentAfter > otherPercent;

    if (!overtookThisParticipant) {
      continue;
    }

    drafts.push({
      type: "overtook",
      recipients: [otherUid],
      target: {kind: "create"},
      payload: {
        competitionTitle,
        actorUid,
        actorUsername,
        targetUid: otherUid,
        targetUsername: otherUsername,
        metadata: {
          actorProgressBefore: beforeProgress,
          actorProgressAfter: afterProgress,
          actorTargetValue,
          actorPercentBefore,
          actorPercentAfter,
          targetProgress: otherProgress,
          targetTargetValue: otherTargetValue,
          targetPercent: otherPercent,
        },
      },
    });
  }

  return drafts;
}
