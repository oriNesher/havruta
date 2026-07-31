import {EventDraft, EventsContext} from "../types";
import {toWholePercent} from "../percent";

const MILESTONE_THRESHOLDS = [25, 50, 75, 90];
const NEAR_COMPLETION_THRESHOLD = 90;

/**
 * Creates progression events for one participant update, strongest first:
 * "won"/"finishedInPosition" when the actor reaches the full target (based
 * on completion order, ahead of everything else and self-guarding since
 * progress only crosses the target once); "nearCompletion" when the actor
 * enters the final stretch without completing; "milestone" for the highest
 * newly-crossed threshold, excluding 90 whenever nearCompletion also fired
 * for the same crossing.
 * @param {EventsContext} context Shared context for this participant update.
 * @return {EventDraft[]} The progression event drafts to persist.
 */
export function detectProgressionEvents(context: EventsContext): EventDraft[] {
  const {
    competitionTitle,
    actorUid,
    actorUsername,
    actorTargetValue,
    beforeProgress,
    afterProgress,
    participantUids,
    completionsCount,
  } = context;

  if (typeof actorTargetValue !== "number" || actorTargetValue <= 0) {
    return [];
  }

  const recipients = participantUids.filter((uid) => uid !== actorUid);
  const wholeBefore = toWholePercent(beforeProgress / actorTargetValue);
  const wholeAfter = toWholePercent(afterProgress / actorTargetValue);

  const justCompleted =
    beforeProgress < actorTargetValue && afterProgress >= actorTargetValue;

  if (justCompleted) {
    const position = completionsCount + 1;
    const type = position === 1 ? "won" : "finishedInPosition";

    // Completion is the strongest progression event: it supersedes both
    // nearCompletion and milestone for this same crossing.
    return [
      {
        type,
        recipients,
        target: {kind: "create"},
        payload: {
          competitionTitle,
          actorUid,
          actorUsername,
          targetUid: null,
          targetUsername: null,
          metadata: {
            position,
            actorProgressBefore: beforeProgress,
            actorProgressAfter: afterProgress,
          },
        },
      },
    ];
  }

  const drafts: EventDraft[] = [];

  const isNearCompletion =
    wholeBefore < NEAR_COMPLETION_THRESHOLD &&
    wholeAfter >= NEAR_COMPLETION_THRESHOLD;

  if (isNearCompletion) {
    drafts.push({
      type: "nearCompletion",
      recipients,
      target: {kind: "create"},
      payload: {
        competitionTitle,
        actorUid,
        actorUsername,
        targetUid: null,
        targetUsername: null,
        metadata: {
          actorPercentBefore: wholeBefore,
          actorPercentAfter: wholeAfter,
        },
      },
    });
  }

  const milestoneThresholds = isNearCompletion ?
    MILESTONE_THRESHOLDS.filter(
      (threshold) => threshold !== NEAR_COMPLETION_THRESHOLD
    ) :
    MILESTONE_THRESHOLDS;

  const crossedMilestones = milestoneThresholds.filter(
    (threshold) => wholeBefore < threshold && wholeAfter >= threshold
  );

  if (crossedMilestones.length > 0) {
    const highestMilestone = Math.max(...crossedMilestones);

    drafts.push({
      type: "milestone",
      recipients,
      target: {kind: "create"},
      payload: {
        competitionTitle,
        actorUid,
        actorUsername,
        targetUid: null,
        targetUsername: null,
        metadata: {
          milestone: highestMilestone,
          actorPercentAfter: wholeAfter,
        },
      },
    });
  }

  return drafts;
}
