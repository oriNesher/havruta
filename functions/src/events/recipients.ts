import {AudienceTier, audienceFor} from "./audience";
import {EventsContext} from "./types";

/**
 * Recipients for an event about the context's actor at the given reach —
 * everyone else in a small challenge, the matching audience in a large one.
 * @param {EventsContext} context The progress update's context.
 * @param {AudienceTier} tier How widely the event should travel.
 * @return {string[]} The recipients.
 */
export function recipientsFor(
  context: EventsContext,
  tier: AudienceTier
): string[] {
  return audienceFor(
    context.audience,
    context.participantUids,
    context.actorUid,
    tier
  );
}
