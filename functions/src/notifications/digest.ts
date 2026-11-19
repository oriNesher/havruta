// The daily digest of a large challenge: one push per person per day, at
// DIGEST_HOUR in the challenge's own time zone, instead of a push per
// report. Pure — the scheduled job (sendDailyDigests) feeds it.
import {ChallengeConfig} from "../challenges/model";
import {rankStandings, StandingParticipant} from "../challenges/standings";

/** Local hour (0–23, challenge time zone) the digest goes out. */
export const DIGEST_HOUR = 20;

/**
 * The hour (0–23) a moment falls on in a time zone; UTC when null or
 * unknown — the same fallback as challengeDayKey.
 * @param {number} millis The moment.
 * @param {string | null} timeZone IANA zone.
 * @return {number} The local hour.
 */
export function localHour(millis: number, timeZone: string | null): number {
  if (timeZone) {
    try {
      const hour = new Intl.DateTimeFormat("en-GB", {
        timeZone,
        hour: "2-digit",
        hourCycle: "h23",
      }).format(new Date(millis));
      return Number(hour);
    } catch {
      // Unknown zone: fall through to UTC.
    }
  }
  return new Date(millis).getUTCHours();
}

/** What one digest run sends and remembers. */
export interface Digest {
  /** Push title. */
  title: string;
  /** The line everyone gets (organizers who don't compete, the out). */
  summary: string;
  /** Per-participant body (the summary plus their own line). */
  bodies: Record<string, string>;
  /** Today's ranks, kept for tomorrow's ▲/▼. */
  ranks: Record<string, number>;
}

/**
 * Builds today's digest. Everyone gets the day in one line ("34 logged
 * today · Dana leads"); each participant adds where they stand — their rank
 * and how it moved since yesterday's digest, or in Last One Standing how
 * much they still need today (it's evening: the most useful nudge there
 * is).
 * @param {object} input Everything the digest needs.
 * @param {string} input.title The challenge's title.
 * @param {ChallengeConfig} input.challenge The challenge.
 * @param {StandingParticipant[]} input.participants Everyone in it.
 * @param {string} input.todayKey Today's challenge day (YYYY-MM-DD).
 * @param {Record<string, number>} input.previousRanks Yesterday's ranks.
 * @return {Digest} The digest.
 */
export function buildDigest(input: {
  title: string;
  challenge: ChallengeConfig;
  participants: StandingParticipant[];
  todayKey: string;
  previousRanks: Record<string, number>;
}): Digest {
  const {challenge, participants, todayKey, previousRanks} = input;
  const ranked = rankStandings(challenge, participants);
  const ranks = Object.fromEntries(ranked.map((p, i) => [p.uid, i + 1]));
  const todayOf = (p: StandingParticipant) => p.dailyProgress[todayKey] ?? 0;
  const logged = participants.filter((p) => todayOf(p) > 0).length;
  const unit = challenge.unit ? ` ${challenge.unit}` : "";
  const los = challenge.winCondition === "lastStanding";

  const parts: string[] = [];
  if (los) {
    const alive = participants.filter((p) => p.eliminatedOnDay === null);
    parts.push(`${alive.length} still in`);
  }
  parts.push(`${logged} logged today`);
  const leader = ranked[0];
  if (!los && leader && leader.progress > 0) {
    parts.push(`${leader.username} leads`);
  }
  const summary = parts.join(" · ");

  const minimum = challenge.rules.dailyMinimum;
  const bodies: Record<string, string> = {};
  for (const p of participants) {
    if (los) {
      if (p.eliminatedOnDay !== null) {
        bodies[p.uid] = summary;
      } else if (minimum && todayOf(p) < minimum) {
        bodies[p.uid] =
          `${summary} · you still need ${minimum - todayOf(p)}${unit} today`;
      } else {
        bodies[p.uid] = `${summary} · you're safe today`;
      }
      continue;
    }
    const rank = ranks[p.uid];
    const before = previousRanks[p.uid];
    const moved = before === undefined || before === rank ? "" :
      before > rank ? ` (▲${before - rank})` : ` (▼${rank - before})`;
    bodies[p.uid] = `${summary} · you're #${rank}${moved}`;
  }

  return {title: `${input.title} today`, summary, bodies, ranks};
}
