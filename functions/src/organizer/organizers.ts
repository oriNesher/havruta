import {OrganizerError} from "./errors";

export const MAX_ORGANIZERS = 10;

/**
 * The organizerUids to backfill onto a challenge created before the
 * organizer role, or null when it needs none. Its creator becomes its
 * organizer — and stays a participant, untouched. Already-migrated docs
 * and docs without a creator are left alone.
 * @param {FirebaseFirestore.DocumentData} data A competitions doc.
 * @return {string[] | null} The organizerUids to write, or null.
 */
export function organizersToBackfill(
  data: FirebaseFirestore.DocumentData
): string[] | null {
  if (Array.isArray(data.organizerUids)) return null;
  return typeof data.createdBy === "string" && data.createdBy ?
    [data.createdBy] :
    null;
}

/**
 * The organizer list after adding or removing one co-organizer. Pure.
 * A challenge always keeps at least one organizer; an organizer may remove
 * themselves as long as someone else remains.
 * @param {string[]} current The current organizerUids.
 * @param {object} change Exactly one of add / remove.
 * @param {string} [change.add] A uid to add.
 * @param {string} [change.remove] A uid to remove.
 * @return {string[]} The new organizerUids.
 * @throws {OrganizerError} When the change isn't allowed.
 */
export function planOrganizerChange(
  current: string[],
  change: {add?: unknown; remove?: unknown}
): string[] {
  const {add, remove} = change;
  const isUid = (v: unknown): v is string => typeof v === "string" && !!v;

  if (isUid(add) === isUid(remove)) {
    throw new OrganizerError("Add or remove exactly one organizer.");
  }

  if (isUid(add)) {
    if (current.includes(add)) {
      throw new OrganizerError("They're already an organizer.");
    }
    if (current.length >= MAX_ORGANIZERS) {
      throw new OrganizerError(
        `A challenge can have at most ${MAX_ORGANIZERS} organizers.`);
    }
    return [...current, add];
  }

  const uid = remove as string;
  if (!current.includes(uid)) {
    throw new OrganizerError("They aren't an organizer.");
  }
  const next = current.filter((u) => u !== uid);
  if (next.length === 0) {
    throw new OrganizerError(
      "A challenge needs at least one organizer. Add someone else first.");
  }
  return next;
}
