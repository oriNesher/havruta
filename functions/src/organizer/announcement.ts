import {OrganizerError} from "./errors";

export const MAX_ANNOUNCEMENT = 500;
/** Announcements a challenge may send per rolling 24 hours. */
export const ANNOUNCEMENTS_PER_DAY = 10;

/**
 * Validates an announcement's text. Pure.
 * @param {unknown} value The raw text.
 * @param {number} sentInLastDay How many this challenge sent in 24h.
 * @return {string} The trimmed text.
 * @throws {OrganizerError} When it's empty, too long, or over the limit.
 */
export function planAnnouncement(
  value: unknown,
  sentInLastDay: number
): string {
  const text = typeof value === "string" ? value.trim() : "";
  if (!text) throw new OrganizerError("Write something to announce.");
  if (text.length > MAX_ANNOUNCEMENT) {
    throw new OrganizerError(
      `Announcements can be at most ${MAX_ANNOUNCEMENT} characters.`);
  }
  if (sentInLastDay >= ANNOUNCEMENTS_PER_DAY) {
    throw new OrganizerError(
      `That's ${ANNOUNCEMENTS_PER_DAY} announcements in the last 24 hours — ` +
        "the limit, so people don't tune them out. Try again later.");
  }
  return text;
}

/**
 * The push notification body: "<organizer>: <text>", shortened to fit a
 * lock screen.
 * @param {string} username The organizer.
 * @param {string} text The announcement.
 * @return {string} The body.
 */
export function announcementPushBody(username: string, text: string): string {
  const body = `${username}: ${text}`;
  return body.length <= 160 ? body : `${body.slice(0, 157).trimEnd()}…`;
}
