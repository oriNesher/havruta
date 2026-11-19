import {OrganizerError} from "./errors";

export const MAX_TEAMS = 50;
export const MAX_TEAM_NAME = 40;

/** The team operations an organizer can run. */
export type TeamOp = "create" | "rename" | "delete" | "assign";

/**
 * A validated team name: trimmed, 1–MAX_TEAM_NAME characters, unique
 * within the challenge regardless of case. Pure.
 * @param {unknown} raw The requested name.
 * @param {string[]} otherNames Every other team's name.
 * @return {string} The name.
 * @throws {OrganizerError} When it's empty, too long or taken.
 */
export function cleanTeamName(raw: unknown, otherNames: string[]): string {
  const name = typeof raw === "string" ? raw.trim() : "";
  if (!name || name.length > MAX_TEAM_NAME) {
    throw new OrganizerError(
      `A team name is 1 to ${MAX_TEAM_NAME} characters.`);
  }
  const lower = name.toLowerCase();
  if (otherNames.some((other) => other.trim().toLowerCase() === lower)) {
    throw new OrganizerError(`There's already a team called "${name}".`);
  }
  return name;
}

/**
 * Validates the op itself (which fields it needs). Pure.
 * @param {unknown} op The requested op.
 * @return {TeamOp} The op.
 * @throws {OrganizerError} For an unknown op.
 */
export function requireTeamOp(op: unknown): TeamOp {
  if (op === "create" || op === "rename" || op === "delete" ||
    op === "assign") {
    return op;
  }
  throw new OrganizerError("Unknown team action.");
}
