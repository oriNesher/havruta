// A challenge's days are calendar days in its timeZone — one calendar for
// every participant, wherever they are. Must agree with Challenge.dayKey in
// lib/competitions/challenge.dart, which keys participants' dailyProgress.

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * The challenge-calendar date (YYYY-MM-DD) a moment falls on.
 * @param {number} millis The moment, in epoch milliseconds.
 * @param {string | null} timeZone The challenge's IANA zone; null is UTC.
 * @return {string} The calendar date in that zone.
 */
export function challengeDayKey(
  millis: number,
  timeZone: string | null
): string {
  if (!timeZone) return new Date(millis).toISOString().slice(0, 10);
  try {
    // en-CA formats dates as YYYY-MM-DD.
    return new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(new Date(millis));
  } catch {
    // An unknown zone name falls back to UTC, as the client does.
    return new Date(millis).toISOString().slice(0, 10);
  }
}

/**
 * Shifts a YYYY-MM-DD date by whole days. Pure date arithmetic, so it's
 * unaffected by DST in any zone.
 * @param {string} dayKey A calendar date.
 * @param {number} days Days to add (negative to go back).
 * @return {string} The shifted calendar date.
 */
export function addDays(dayKey: string, days: number): string {
  const base = Date.parse(`${dayKey}T00:00:00Z`);
  return new Date(base + days * MS_PER_DAY).toISOString().slice(0, 10);
}

/**
 * Whole days from one calendar date to another (b - a).
 * @param {string} a The earlier calendar date.
 * @param {string} b The later calendar date.
 * @return {number} The number of days between them.
 */
export function daysBetween(a: string, b: string): number {
  return Math.round(
    (Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / MS_PER_DAY
  );
}
