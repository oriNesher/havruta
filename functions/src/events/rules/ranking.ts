import {EventDraft, EventsContext} from "../types";

const TOOK_THE_LEAD_MIN_PARTICIPANTS = 3;

/**
 * Creates ranking events for one participant update: "overtook" for each
 * participant just passed, "tied" for each participant just matched, and
 * "tookTheLead" if the actor just became the competition's sole leader.
 * @param {EventsContext} context Shared context for this participant update.
 * @return {EventDraft[]} The ranking event drafts to persist.
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
    participantUids,
  } = context;

  if (typeof actorTargetValue !== "number" || actorTargetValue <= 0) {
    return [];
  }

  const actorPercentBefore = beforeProgress / actorTargetValue;
  const actorPercentAfter = afterProgress / actorTargetValue;

  const drafts: EventDraft[] = [];
  let maxOtherPercent = -Infinity;

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
    maxOtherPercent = Math.max(maxOtherPercent, otherPercent);

    // Overtook only if the actor was not ahead before and is ahead now.
    const overtookThisParticipant =
      actorPercentBefore <= otherPercent && actorPercentAfter > otherPercent;

    if (overtookThisParticipant) {
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

    // Tied only on the transition into equal percentages, not while already
    // tied, so it can fire again after a later break.
    const justTiedWithParticipant =
      actorPercentBefore !== otherPercent && actorPercentAfter === otherPercent;

    if (justTiedWithParticipant) {
      drafts.push({
        type: "tied",
        recipients: [otherUid],
        target: {kind: "create"},
        payload: {
          competitionTitle,
          actorUid,
          actorUsername,
          targetUid: otherUid,
          targetUsername: otherUsername,
          metadata: {
            tiedPercent: otherPercent,
            actorProgressAfter: afterProgress,
            targetProgress: otherProgress,
          },
        },
      });
    }
  }

  const hasValidOthers = maxOtherPercent > -Infinity;
  const wasSoleLeaderBefore =
    hasValidOthers && actorPercentBefore > maxOtherPercent;
  const isSoleLeaderAfter =
    hasValidOthers && actorPercentAfter > maxOtherPercent;

  if (
    participantUids.length >= TOOK_THE_LEAD_MIN_PARTICIPANTS &&
    !wasSoleLeaderBefore &&
    isSoleLeaderAfter
  ) {
    drafts.push({
      type: "tookTheLead",
      recipients: participantUids.filter((uid) => uid !== actorUid),
      target: {kind: "create"},
      payload: {
        competitionTitle,
        actorUid,
        actorUsername,
        targetUid: null,
        targetUsername: null,
        metadata: {
          actorProgressBefore: beforeProgress,
          actorProgressAfter: afterProgress,
          actorPercentBefore,
          actorPercentAfter,
        },
      },
    });
  }

  return drafts;
}
