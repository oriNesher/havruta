/**
 * A refused organizer action, with a message fit to show the organizer.
 * The pure planners throw it; the callables turn it into an HttpsError.
 */
export class OrganizerError extends Error {
  /**
   * @param {string} message User-facing reason.
   */
  constructor(message: string) {
    super(message);
    this.name = "OrganizerError";
  }
}
