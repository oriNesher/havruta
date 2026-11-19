import {ChallengeConfig} from "../challenges/model";
import {StandingParticipant} from "../challenges/standings";
import {OrganizerError} from "./errors";

/** What an organizer asked to change. Times are epoch millis. */
export interface SettingsPatch {
  title?: unknown;
  description?: unknown;
  startsAtMillis?: unknown;
  /** null removes the end date (not allowed for Most Progress). */
  endsAtMillis?: unknown;
  dailyMinimum?: unknown;
  targetValue?: unknown;
  /** "auto" | "small" | "large" (see isLargeChallenge). */
  scale?: unknown;
  /** true / false, or null to go back to the default. */
  trashTalk?: unknown;
}

/** One changed field, for the audit log. */
export interface FieldChange {
  before: unknown;
  after: unknown;
}

/** The validated change, only the fields that actually differ. */
export interface SettingsPlan {
  title?: string;
  description?: string;
  startsAtMillis?: number;
  endsAtMillis?: number | null;
  dailyMinimum?: number;
  /**
   * The new race target. Also copied onto every participant doc, since
   * standings read a participant's own targetValue first.
   */
  targetValue?: number;
  scale?: "auto" | "small" | "large";
  trashTalk?: boolean | null;
  changes: Record<string, FieldChange>;
}

const MAX_TITLE = 80;
const MAX_DESCRIPTION = 2000;

/**
 * Validates an organizer's edit of a running challenge. Pure, so the
 * callable's transaction and the tests share it.
 * - Title and description: any time, even after the challenge is over.
 * - Everything else only while it runs (active, before its end). The win
 *   condition itself is never editable.
 * - Start: only before the challenge has started, to a future time before
 *   its end. A challenge with no start began when it was created.
 * - End: to a future time after the start; removed only where an end isn't
 *   required (not Most Progress).
 * - Daily minimum (Last One Standing): applies from the first day not yet
 *   judged, which includes today.
 * - Race target: raised any time; lowered only while nobody's progress is
 *   at or above the new target, so an edit never crowns or finishes anyone.
 * @param {ChallengeConfig} challenge The challenge, read transactionally.
 * @param {{title: string, description: string}} current Its display text.
 * @param {StandingParticipant[]} participants Everyone in it (needed only
 *   to judge a lowered target).
 * @param {SettingsPatch} patch The requested change.
 * @param {number} nowMillis The current time.
 * @return {SettingsPlan} The validated change.
 * @throws {OrganizerError} When the change isn't allowed.
 */
export function planSettingsChange(
  challenge: ChallengeConfig,
  current: {title: string; description: string},
  participants: StandingParticipant[],
  patch: SettingsPatch,
  nowMillis: number
): SettingsPlan {
  const plan: SettingsPlan = {changes: {}};
  const has = (key: keyof SettingsPatch) => patch[key] !== undefined;

  if (has("title")) {
    const title = typeof patch.title === "string" ? patch.title.trim() : "";
    if (!title || title.length > MAX_TITLE) {
      throw new OrganizerError(
        `The title must be 1 to ${MAX_TITLE} characters.`);
    }
    if (title !== current.title) {
      plan.title = title;
      plan.changes.title = {before: current.title, after: title};
    }
  }

  if (has("description")) {
    if (typeof patch.description !== "string" ||
      patch.description.length > MAX_DESCRIPTION) {
      throw new OrganizerError(
        `The description can be at most ${MAX_DESCRIPTION} characters.`);
    }
    const description = patch.description.trim();
    if (description !== current.description) {
      plan.description = description;
      plan.changes.description =
        {before: current.description, after: description};
    }
  }

  const editsDefinition = has("startsAtMillis") || has("endsAtMillis") ||
    has("dailyMinimum") || has("targetValue");
  if (editsDefinition) {
    const endsAt = challenge.endsAt?.toMillis() ?? null;
    if (challenge.status !== "active" ||
      (endsAt !== null && endsAt <= nowMillis)) {
      throw new OrganizerError(
        "This challenge is over, so its rules can't change.");
    }
  }

  const currentStart = challenge.startsAt?.toMillis() ?? null;
  const currentEnd = challenge.endsAt?.toMillis() ?? null;
  let effectiveStart = currentStart;

  if (has("startsAtMillis")) {
    const startsAt = patch.startsAtMillis;
    if (typeof startsAt !== "number" || !Number.isFinite(startsAt)) {
      throw new OrganizerError("Pick a valid start time.");
    }
    if (startsAt !== currentStart) {
      if (currentStart === null || currentStart <= nowMillis) {
        throw new OrganizerError(
          "This challenge has already started, so its start can't move.");
      }
      if (startsAt <= nowMillis) {
        throw new OrganizerError("The new start has to be in the future.");
      }
      plan.startsAtMillis = startsAt;
      plan.changes.startsAt = {before: iso(currentStart), after: iso(startsAt)};
      effectiveStart = startsAt;
    }
  }

  let effectiveEnd = currentEnd;
  if (has("endsAtMillis")) {
    const endsAt = patch.endsAtMillis;
    if (endsAt === null) {
      if (challenge.winCondition === "mostProgress") {
        throw new OrganizerError(
          "A Most Progress challenge needs an end date.");
      }
    } else if (typeof endsAt !== "number" || !Number.isFinite(endsAt)) {
      throw new OrganizerError("Pick a valid end time.");
    } else if (endsAt <= nowMillis) {
      throw new OrganizerError(
        "The new end has to be in the future. To stop now, end the " +
          "challenge early instead.");
    }
    if (endsAt !== currentEnd) {
      plan.endsAtMillis = endsAt as number | null;
      plan.changes.endsAt = {
        before: iso(currentEnd),
        after: iso(endsAt as number | null),
      };
      effectiveEnd = endsAt as number | null;
    }
  }

  if (effectiveStart !== null && effectiveEnd !== null &&
    effectiveEnd <= effectiveStart) {
    throw new OrganizerError("The end has to be after the start.");
  }

  if (has("dailyMinimum")) {
    if (challenge.winCondition !== "lastStanding") {
      throw new OrganizerError(
        "Only Last One Standing challenges have a daily minimum.");
    }
    const minimum = patch.dailyMinimum;
    if (!isPositiveInteger(minimum)) {
      throw new OrganizerError(
        "The daily minimum must be a whole number above 0.");
    }
    if (minimum !== challenge.rules.dailyMinimum) {
      plan.dailyMinimum = minimum;
      plan.changes.dailyMinimum = {
        before: challenge.rules.dailyMinimum,
        after: minimum,
      };
    }
  }

  if (has("targetValue")) {
    if (challenge.winCondition !== "firstToTarget" ||
      challenge.isLegacyPersonal) {
      throw new OrganizerError("Only a Race has a shared target to change.");
    }
    const target = patch.targetValue;
    if (!isPositiveInteger(target)) {
      throw new OrganizerError("The target must be a whole number above 0.");
    }
    const before = challenge.targetValue;
    if (target !== before) {
      if (before !== null && target < before) {
        const reached = participants.filter((p) => p.progress >= target);
        if (reached.length > 0) {
          throw new OrganizerError(
            `Can't lower the target to ${target}: ` +
              `${reached.map((p) => p.username).join(", ")} ` +
              "already reached it. Raise it, or pick a target above " +
              "everyone's progress.");
        }
      }
      plan.targetValue = target;
      plan.changes.targetValue = {before, after: target};
    }
  }

  if (has("scale") || has("trashTalk")) {
    if (challenge.status !== "active") {
      throw new OrganizerError(
        "This challenge is over, so its settings can't change.");
    }
  }
  if (has("scale")) {
    const scale = patch.scale;
    if (scale !== "auto" && scale !== "small" && scale !== "large") {
      throw new OrganizerError("Pick automatic, small or large.");
    }
    if (scale !== challenge.social.scale) {
      plan.scale = scale;
      plan.changes.scale = {before: challenge.social.scale, after: scale};
    }
  }
  if (has("trashTalk")) {
    const trashTalk = patch.trashTalk;
    if (trashTalk !== null && typeof trashTalk !== "boolean") {
      throw new OrganizerError("Trash Talk is either on or off.");
    }
    if (trashTalk !== challenge.social.trashTalk) {
      plan.trashTalk = trashTalk;
      plan.changes.trashTalk = {
        before: challenge.social.trashTalk,
        after: trashTalk,
      };
    }
  }

  if (Object.keys(plan.changes).length === 0) {
    throw new OrganizerError("Nothing changed.");
  }
  return plan;
}

/**
 * Whether a value is a whole number above 0.
 * @param {unknown} value The value.
 * @return {boolean} True for 1, 2, 3, …
 */
function isPositiveInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value > 0;
}

/**
 * A time for the audit log.
 * @param {number | null} millis Epoch millis, or null.
 * @return {string | null} ISO-8601, or null.
 */
function iso(millis: number | null): string | null {
  return millis === null ? null : new Date(millis).toISOString();
}
