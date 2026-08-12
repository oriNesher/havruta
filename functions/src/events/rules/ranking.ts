import {EventDraft, EventsContext, ExistingOpenEvent} from "../types";
import {toWholePercent} from "../percent";

const TOOK_THE_LEAD_MIN_PARTICIPANTS = 3;

/**
 * Finds an already-open "tied" event for this exact unordered pair, so a
 * repeat tie between the same two participants updates it instead of
 * creating a duplicate.
 * @param {ExistingOpenEvent[]} openTiedEvents Open tied events for the
 *   competition.
 * @param {string} uidA One participant's uid.
 * @param {string} uidB The other participant's uid.
 * @return {ExistingOpenEvent | null} The matching event, if any.
 */
function findOpenTiedEvent(
  openTiedEvents: ExistingOpenEvent[],
  uidA: string,
  uidB: string
): ExistingOpenEvent | null {
  return (
    openTiedEvents.find((existing) => {
      const a = existing.data.actorUid;
      const b = existing.data.targetUid;
      return (a === uidA && b === uidB) || (a === uidB && b === uidA);
    }) ?? null
  );
}

/**
 * Creates ranking events for one participant update: "overtook" for each
 * participant just passed, "tied" for each participant just matched, and
 * "tookTheLead" if the actor just became the competition's sole leader.
 * All comparisons use whole-percent rounding so overtook/tied stay mutually
 * exclusive for the same pair.
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
    openTiedEvents,
  } = context;

  if (typeof actorTargetValue !== "number" || actorTargetValue <= 0) {
    return [];
  }

  const actorPercentBefore = beforeProgress / actorTargetValue;
  const actorPercentAfter = afterProgress / actorTargetValue;
  const actorWholeBefore = toWholePercent(actorPercentBefore);
  const actorWholeAfter = toWholePercent(actorPercentAfter);

  const drafts: EventDraft[] = [];
  let maxOtherWhole = -Infinity;

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
    const otherWhole = toWholePercent(otherPercent);
    maxOtherWhole = Math.max(maxOtherWhole, otherWhole);

    // Overtook only if the actor was not ahead before and is ahead now.
    const overtookThisParticipant =
      actorWholeBefore <= otherWhole && actorWholeAfter > otherWhole;

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

    // Tied only on the transition into equal whole percentages, not while
    // already tied, so it can fire again after a later break.
    const justTiedWithParticipant =
      actorWholeBefore !== otherWhole && actorWholeAfter === otherWhole;

    if (justTiedWithParticipant) {
      const existingTied =
        findOpenTiedEvent(openTiedEvents, actorUid, otherUid);

      drafts.push({
        type: "tied",
        recipients: [otherUid],
        target: existingTied ?
          {kind: "update", docId: existingTied.id} :
          {kind: "create"},
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

  const hasValidOthers = maxOtherWhole > -Infinity;
  const wasSoleLeaderBefore =
    hasValidOthers && actorWholeBefore > maxOtherWhole;
  const isSoleLeaderAfter =
    hasValidOthers && actorWholeAfter > maxOtherWhole;

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
