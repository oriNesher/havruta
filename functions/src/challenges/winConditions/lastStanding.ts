import {addDays, challengeDayKey, daysBetween} from "../calendar";
import {ChallengeConfig} from "../model";
import {StandingParticipant} from "../standings";

export interface Elimination {
  uid: string;
  /** The challenge day they missed (YYYY-MM-DD). */
  day: string;
  /** That day's 1-based number, counting from day 1. */
  dayNumber: number;
}

export interface LastStandingResult {
  /** Fields to write to the competition doc, or null for no write. */
  update: Record<string, unknown> | null;
  eliminations: Elimination[];
  completes: boolean;
  winnerUids: string[];
}

const NO_CHANGE: LastStandingResult = {
  update: null,
  eliminations: [],
  completes: false,
  winnerUids: [],
};

/**
 * Judges every Last One Standing day that has ended since the last run,
 * and decides whether the challenge is over. Pure, so the scheduled job
 * can run it inside a transaction and tests can cover every case.
 *
 * - A day ends at midnight in the challenge's timeZone. Each participant
 *   still in who logged less than rules.dailyMinimum that day is out.
 *   Someone who joined after a day began isn't judged on it.
 * - One left (of a challenge that began with 2+) wins.
 * - Everyone still in missing the same day: the most progress that day
 *   wins, then the most total progress; still tied, they share the win.
 * - Reaching endsAt with several still in: they share the win.
 * - A solo challenge never declares a winner by outlasting — its one
 *   participant wins only by surviving to endsAt.
 * Days are judged one at a time from lastEvaluatedDay, so a missed run
 * catches up rather than skipping days.
 * @param {ChallengeConfig} challenge The challenge, read transactionally.
 * @param {StandingParticipant[]} participants Everyone in it.
 * @param {number} nowMillis The current time.
 * @return {LastStandingResult} What to write and announce.
 */
export function evaluateLastStanding(
  challenge: ChallengeConfig,
  participants: StandingParticipant[],
  nowMillis: number
): LastStandingResult {
  const minimum = challenge.rules.dailyMinimum;
  const startsAt = challenge.startsAt;
  if (challenge.status !== "active" || !minimum || !startsAt) {
    return NO_CHANGE;
  }

  const zone = challenge.timeZone;
  const startDay = challengeDayKey(startsAt.toMillis(), zone);
  const today = challengeDayKey(nowMillis, zone);
  // Day 1 hasn't ended yet: nothing to judge.
  if (today <= startDay) return NO_CHANGE;

  const endsAt = challenge.endsAt;
  const finalDay = endsAt ?
    challengeDayKey(endsAt.toMillis() - 1, zone) :
    null;
  const yesterday = addDays(today, -1);
  const lastClosedDay = finalDay && finalDay < yesterday ? finalDay : yesterday;

  const startingCount =
    challenge.startingParticipantCount ?? participants.length;
  const canOutlast = startingCount >= 2;

  let alive = participants.filter((p) => p.eliminatedOnDay === null);
  const eliminations: Elimination[] = [];
  let cursor = challenge.lastEvaluatedDay;
  let winnerUids: string[] = [];
  let completes = false;

  const eliminate = (out: StandingParticipant[], day: string) => {
    for (const p of out) {
      eliminations.push({
        uid: p.uid,
        day,
        dayNumber: daysBetween(startDay, day) + 1,
      });
    }
    const outUids = new Set(out.map((p) => p.uid));
    alive = alive.filter((p) => !outUids.has(p.uid));
  };

  for (
    let day = cursor ? addDays(cursor, 1) : startDay;
    day <= lastClosedDay;
    day = addDays(day, 1)
  ) {
    const judged = alive.filter((p) => p.joinedDay === null ||
      p.joinedDay <= day);
    const missed = judged.filter((p) =>
      (p.dailyProgress[day] ?? 0) < minimum);
    cursor = day;

    if (missed.length > 0 && missed.length === alive.length) {
      if (canOutlast) {
        winnerUids = bestOfTheDay(missed, day).map((p) => p.uid);
        eliminate(missed.filter((p) => !winnerUids.includes(p.uid)), day);
      } else {
        eliminate(missed, day);
      }
      completes = true;
      break;
    }

    eliminate(missed, day);

    if (canOutlast && alive.length === 1) {
      winnerUids = [alive[0].uid];
      completes = true;
      break;
    }
  }

  if (!completes) {
    if (canOutlast && alive.length === 1) {
      // Down to one without a new day judged — someone else left.
      winnerUids = [alive[0].uid];
      completes = true;
    } else if (alive.length === 0) {
      // A solo participant out, or everyone left: over, nobody won.
      completes = true;
    } else if (finalDay && cursor !== null && cursor >= finalDay) {
      winnerUids = alive.map((p) => p.uid);
      completes = true;
    }
  }

  const update: Record<string, unknown> = {};
  if (cursor !== challenge.lastEvaluatedDay) update.lastEvaluatedDay = cursor;
  if (challenge.startingParticipantCount === null) {
    update.startingParticipantCount = startingCount;
  }
  if (completes) {
    update.status = "completed";
    update.winnerUids = winnerUids;
    update.winnerUid = winnerUids[0] ?? null;
  }

  return {
    update: Object.keys(update).length > 0 ? update : null,
    eliminations,
    completes,
    winnerUids,
  };
}

/**
 * Among participants who all missed the same day, the ones who came
 * closest: most progress that day, then most total progress.
 * @param {StandingParticipant[]} missed Everyone who missed the day.
 * @param {string} day The day they missed.
 * @return {StandingParticipant[]} The tied best (usually one).
 */
function bestOfTheDay(
  missed: StandingParticipant[],
  day: string
): StandingParticipant[] {
  const onDay = (p: StandingParticipant) => p.dailyProgress[day] ?? 0;
  const bestDay = Math.max(...missed.map(onDay));
  const closest = missed.filter((p) => onDay(p) === bestDay);
  const bestTotal = Math.max(...closest.map((p) => p.progress));
  return closest.filter((p) => p.progress === bestTotal);
}
