/**
 * Event types the actor gets a full-screen celebration for. Kept in sync
 * by hand with the client's copy at lib/celebrations/celebration_types.dart
 * — there's no shared codegen between the functions and Flutter packages.
 */
export const CELEBRATION_TYPES = [
  "firstBlood",
  "overtook",
  "tookTheLead",
  "pullingAhead",
  "milestone",
  "nearCompletion",
  "activityStreak",
  "backInRace",
  "won",
  "finishedInPosition",
  "progress",
] as const;

/**
 * Whether an event type should carry the actor-celebration fields
 * (actorCelebrated, batchId) when persisted.
 * @param {string} type The event's type string.
 * @return {boolean} True if this type is celebration-eligible.
 */
export function isCelebrationType(type: string): boolean {
  return (CELEBRATION_TYPES as readonly string[]).includes(type);
}
