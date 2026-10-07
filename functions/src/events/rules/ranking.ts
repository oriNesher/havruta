import {EventDraft, EventsContext, ExistingOpenEvent} from "../types";
import {toWholePercent} from "../percent";
import {ChallengeConfig} from "../../challenges/model";

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
 * What participants are ranked by: whole percent of target in a race (so
 * participants with different targets compare fairly), the raw total in
 * Most Progress. Null when it can't be scored (a race participant with no
 * target).
 * @param {ChallengeConfig} challenge The challenge.
 * @param {number} progress The participant's progress.
 * @param {number | undefined} targetValue The participant's target.
 * @return {number | null} The comparable score.
 */
function rankingScore(
  challenge: ChallengeConfig,
  progress: number,
  targetValue: number | undefined
): number | null {
  if (challenge.winCondition === "mostProgress") return progress;
  if (typeof targetValue !== "number" || targetValue <= 0) return null;
  return toWholePercent(progress / targetValue);
}

/**
 * progress / target, or null without a target (Most Progress).
 * @param {number} progress A progress value.
 * @param {number | undefined} targetValue The matching target.
 * @return {number | null} The fraction.
 */
function fractionOrNull(
  progress: number,
  targetValue: number | undefined
): number | null {
  return typeof targetValue === "number" && targetValue > 0 ?
    progress / targetValue :
    null;
}

/**
 * Creates ranking events for one participant update: "overtook" for each
 * participant just passed, "tied" for each participant just matched, and
 * "tookTheLead" if the actor just became the competition's sole leader.
 * Races compare whole-percent rounding so overtook/tied stay mutually
 * exclusive for the same pair; Most Progress compares raw totals. Last One
 * Standing has no ranking to speak of — surviving is what counts.
 * @param {EventsContext} context Shared context for this participant update.
 * @return {EventDraft[]} The ranking event drafts to persist.
 */
export function detectRankingEvents(context: EventsContext): EventDraft[] {
  const {
    competitionTitle,
    challenge,
    actorUid,
    actorUsername,
    actorTargetValue,
    beforeProgress,
    afterProgress,
    participants,
    participantUids,
    openTiedEvents,
  } = context;

  if (challenge.winCondition === "lastStanding") {
    return [];
  }

  const actorWholeBefore =
    rankingScore(challenge, beforeProgress, actorTargetValue);
  const actorWholeAfter =
    rankingScore(challenge, afterProgress, actorTargetValue);

  if (actorWholeBefore === null || actorWholeAfter === null) {
    return [];
  }

  const actorPercentBefore = fractionOrNull(beforeProgress, actorTargetValue);
  const actorPercentAfter = fractionOrNull(afterProgress, actorTargetValue);

  const drafts: EventDraft[] = [];
  let maxOtherWhole = -Infinity;

  for (const participant of participants) {
    const otherUid = participant.uid;

    if (!otherUid || otherUid === actorUid) {
      continue;
    }

    const otherUsername = participant.username ?? "Someone";
    const otherProgress = participant.progress ?? 0;
    const otherTargetValue = participant.targetValue;

    const otherWhole =
      rankingScore(challenge, otherProgress, otherTargetValue);
    if (otherWhole === null) {
      continue;
    }

    const otherPercent = fractionOrNull(otherProgress, otherTargetValue);
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
