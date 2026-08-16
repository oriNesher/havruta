/**
 * Isolated closed-beta content for the invite landing page. Everything the
 * beta gate needs lives here — the invite schema, callables, and App Links
 * setup never reference this file directly, only landingHandler.ts does.
 *
 * To retire the beta gate once Havruta is publicly available: set
 * `enabled` to false (or delete this file and the one `if` block in
 * landingHandler.ts that reads it). No other file needs to change.
 *
 * TODO(you): fill in the real URLs below before deploying.
 */
export const BETA_GATE_CONFIG = {
  enabled: true,
  googleGroupUrl: "https://groups.google.com/g/havruta-beta-testers",
  playListingUrl: "https://play.google.com/store/apps/details?id=com.orinesher.havruta&pli=1",
  instructions:
    "Havruta is in closed testing right now. Join our testers group, " +
    "then open the Play Store link below to install the beta.",
};
