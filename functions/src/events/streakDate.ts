const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * Formats a timestamp as a UTC calendar date string (YYYY-MM-DD), used as
 * the unit of "one active day" regardless of how many updates land on it.
 * @param {FirebaseFirestore.Timestamp} timestamp The moment to format.
 * @return {string} The UTC calendar date.
 */
export function toDateString(timestamp: FirebaseFirestore.Timestamp): string {
  return timestamp.toDate().toISOString().slice(0, 10);
}

/**
 * Returns whether currentDateStr is exactly one UTC calendar day after
 * previousDateStr.
 * @param {string} previousDateStr A UTC calendar date (YYYY-MM-DD).
 * @param {string} currentDateStr A UTC calendar date (YYYY-MM-DD).
 * @return {boolean} True if currentDateStr is the day right after.
 */
export function isNextCalendarDay(
  previousDateStr: string,
  currentDateStr: string
): boolean {
  const previous = new Date(`${previousDateStr}T00:00:00Z`).getTime();
  const current = new Date(`${currentDateStr}T00:00:00Z`).getTime();
  return Math.round((current - previous) / MS_PER_DAY) === 1;
}
