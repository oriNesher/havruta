import {EventDraft, EventsContext} from "../types";
import {toWholePercent} from "../percent";

const CLOSE_THRESHOLD_POINTS = 5;
const PULLING_AHEAD_THRESHOLD_POINTS = 3;
const CLOSE_RACE_CHECKPOINT = 90;
const CLOSE_RACE_GAP_THRESHOLD_POINTS = 4;

interface OtherPercent {
  uid: string;
  username: string;
  whole: number;
}

/**
 * Returns the leader's and second-place whole percent among a set of
 * participants (ties for first count as leader === second, a zero gap).
 * @param {number[]} wholePercents Whole percents for every participant.
 * @return {{leader: number, second: number}} The top two whole percents.
 */
function topTwo(wholePercents: number[]): {leader: number; second: number} {
  const sorted = [...wholePercents].sort((a, b) => b - a);
  return {leader: sorted[0], second: sorted[1] ?? sorted[0]};
}

/**
 * Creates competitive-gap events: "closeBehindYou" when the actor newly
 * enters a close range behind someone, "pullingAhead" when the actor (as
 * leader) newly opens a meaningful gap over 2nd place, and "closeRace" when
 * the leader crosses a checkpoint while still in a close race for 1st.
 * @param {EventsContext} context Shared context for this participant update.
 * @return {EventDraft[]} The gap event drafts to persist.
 */
export function detectGapEvents(context: EventsContext): EventDraft[] {
  const {
    competitionTitle,
    actorUid,
    actorUsername,
    actorTargetValue,
    beforeProgress,
    afterProgress,
    participants,
    participantUids,
    firedCloseRaceCheckpoints,
  } = context;

  if (typeof actorTargetValue !== "number" || actorTargetValue <= 0) {
    return [];
  }

  const actorWholeBefore = toWholePercent(beforeProgress / actorTargetValue);
  const actorWholeAfter = toWholePercent(afterProgress / actorTargetValue);

  const others: OtherPercent[] = participants
    .filter((p) => p.uid && p.uid !== actorUid)
    .filter(
      (p) => typeof p.targetValue === "number" && (p.targetValue as number) > 0
    )
    .map((p) => ({
      uid: p.uid,
      username: p.username ?? "Someone",
      whole: toWholePercent((p.progress ?? 0) / (p.targetValue as number)),
    }));

  const drafts: EventDraft[] = [];

  for (const other of others) {
    const gapBefore = other.whole - actorWholeBefore;
    const gapAfter = other.whole - actorWholeAfter;

    // Crossing into the close range from behind, not a tie/overtake (those
    // have gapAfter <= 0) and not merely remaining inside the range.
    const enteredCloseRange =
      gapBefore > CLOSE_THRESHOLD_POINTS &&
      gapAfter > 0 &&
      gapAfter <= CLOSE_THRESHOLD_POINTS;

    if (enteredCloseRange) {
      drafts.push({
        type: "closeBehindYou",
        recipients: [other.uid],
        target: {kind: "create"},
        payload: {
          competitionTitle,
          actorUid,
          actorUsername,
          targetUid: other.uid,
          targetUsername: other.username,
          metadata: {
            actorPercent: actorWholeAfter,
            targetPercent: other.whole,
            gap: gapAfter,
          },
        },
      });
    }
  }

  const otherWholes = others.map((o) => o.whole);

  if (otherWholes.length > 0) {
    const before = topTwo([...otherWholes, actorWholeBefore]);
    const after = topTwo([...otherWholes, actorWholeAfter]);
    const recipients = participantUids.filter((uid) => uid !== actorUid);

    // Only the actor's own move can have caused the leader gap to widen, so
    // this implies the actor is the (possibly new) leader.
    const justPulledAhead =
      before.leader - before.second < PULLING_AHEAD_THRESHOLD_POINTS &&
      after.leader - after.second >= PULLING_AHEAD_THRESHOLD_POINTS;

    if (justPulledAhead) {
      drafts.push({
        type: "pullingAhead",
        recipients,
        target: {kind: "create"},
        payload: {
          competitionTitle,
          actorUid,
          actorUsername,
          targetUid: null,
          targetUsername: null,
          metadata: {
            leaderPercent: after.leader,
            secondPercent: after.second,
            gap: after.leader - after.second,
          },
        },
      });
    }

    // The checkpoint only becomes reachable when the leader's own percent
    // moves past it, which (since only the actor changed) means the actor
    // drove it.
    const crossedCloseRaceCheckpoint =
      before.leader < CLOSE_RACE_CHECKPOINT &&
      after.leader >= CLOSE_RACE_CHECKPOINT &&
      !firedCloseRaceCheckpoints.includes(CLOSE_RACE_CHECKPOINT);

    if (crossedCloseRaceCheckpoint) {
      const gapAtCheckpoint = after.leader - after.second;

      if (gapAtCheckpoint < CLOSE_RACE_GAP_THRESHOLD_POINTS) {
        drafts.push({
          type: "closeRace",
          recipients,
          target: {kind: "create"},
          payload: {
            competitionTitle,
            actorUid,
            actorUsername,
            targetUid: null,
            targetUsername: null,
            metadata: {
              checkpoint: CLOSE_RACE_CHECKPOINT,
              leaderPercent: after.leader,
              secondPercent: after.second,
              gap: gapAtCheckpoint,
            },
          },
        });
      }
    }
  }

  return drafts;
}
