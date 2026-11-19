import {challengeDayKey} from "../challenges/calendar";
import {ChallengeConfig} from "../challenges/model";
import {StandingParticipant} from "../challenges/standings";
import {OrganizerError} from "./errors";

/** A validated organizer correction of one participant's total. */
export interface CorrectionPlan {
  from: number;
  to: number;
  /** to - from; negative for a reduction. */
  delta: number;
  /** The challenge day whose Daily Progress Ledger bucket absorbs it. */
  dayKey: string;
  /** That bucket's value afterwards. */
  dayAmount: number;
}

const DAY_KEY = /^\d{4}-\d{2}-\d{2}$/;
export const MAX_REASON = 500;

/**
 * Validates an organizer setting a participant's progress to a new total.
 * The difference lands on one challenge day (today unless the organizer
 * picks another), so the daily ledger — what Last One Standing judges and
 * the Aggressor Badge reads — stays consistent with the total. Pure.
 * - Only while the challenge runs, and not for someone eliminated.
 * - The day must be one the challenge has had (from its start to today);
 *   in Last One Standing it must not be judged yet, since a correction
 *   can't retroactively change an elimination.
 * - A day's bucket can't go below zero: a reduction comes off a day that
 *   actually had that much logged.
 * @param {ChallengeConfig} challenge The challenge, read transactionally.
 * @param {StandingParticipant} participant Who's being corrected.
 * @param {unknown} newProgress The requested total.
 * @param {unknown} requestedDay A YYYY-MM-DD challenge day, or undefined.
 * @param {number} nowMillis The current time.
 * @return {CorrectionPlan} The validated correction.
 * @throws {OrganizerError} When the correction isn't allowed.
 */
export function planCorrection(
  challenge: ChallengeConfig,
  participant: StandingParticipant,
  newProgress: unknown,
  requestedDay: unknown,
  nowMillis: number
): CorrectionPlan {
  const endsAt = challenge.endsAt?.toMillis() ?? null;
  if (challenge.status !== "active" ||
    (endsAt !== null && endsAt <= nowMillis)) {
    throw new OrganizerError("This challenge is over; its results are final.");
  }
  if (participant.eliminatedOnDay !== null) {
    throw new OrganizerError(
      `${participant.username} is already eliminated.`);
  }
  if (typeof newProgress !== "number" || !Number.isInteger(newProgress) ||
    newProgress < 0) {
    throw new OrganizerError(
      "The new total must be a whole number, 0 or more.");
  }

  const delta = newProgress - participant.progress;
  if (delta === 0) {
    throw new OrganizerError(
      `${participant.username} already has ${newProgress}.`);
  }

  const today = challengeDayKey(nowMillis, challenge.timeZone);
  let dayKey = today;
  if (requestedDay !== undefined && requestedDay !== null) {
    if (typeof requestedDay !== "string" || !DAY_KEY.test(requestedDay)) {
      throw new OrganizerError("Pick a valid day.");
    }
    dayKey = requestedDay;
  }
  if (dayKey > today) {
    throw new OrganizerError("A correction can't land on a future day.");
  }
  const startDay = challenge.startsAt ?
    challengeDayKey(challenge.startsAt.toMillis(), challenge.timeZone) :
    null;
  if (startDay !== null && dayKey < startDay) {
    throw new OrganizerError("That day is before the challenge started.");
  }
  if (challenge.winCondition === "lastStanding" &&
    challenge.lastEvaluatedDay !== null &&
    dayKey <= challenge.lastEvaluatedDay) {
    throw new OrganizerError(
      "That day has already been judged. Corrections can only change " +
        "days that haven't been judged yet.");
  }

  const dayAmount = (participant.dailyProgress[dayKey] ?? 0) + delta;
  if (dayAmount < 0) {
    throw new OrganizerError(
      `Only ${participant.dailyProgress[dayKey] ?? 0} was logged on ` +
        `${dayKey}, so at most that much can come off it.`);
  }

  return {
    from: participant.progress,
    to: newProgress,
    delta,
    dayKey,
    dayAmount,
  };
}

/**
 * A required, trimmed reason for an organizer action.
 * @param {unknown} value The raw reason.
 * @return {string} The trimmed reason.
 * @throws {OrganizerError} When it's missing or too long.
 */
export function requireReason(value: unknown): string {
  const reason = typeof value === "string" ? value.trim() : "";
  if (!reason || reason.length > MAX_REASON) {
    throw new OrganizerError(
      `Add a reason (up to ${MAX_REASON} characters) — it goes in the ` +
        "audit log.");
  }
  return reason;
}
