/**
 * Isolated closed-beta content for the invite landing page. Everything the
 * beta gate needs lives here — the invite schema, callables, and App Links
 * setup never reference this file directly, only landingHandler.ts does.
 *
 * Since the web app shipped this is the secondary route, not the only one:
 * the landing page offers "Open in browser" above this section, which needs
 * no install and no testers-group membership. The copy below is written to
 * read as "if you'd rather have the native app", not as a toll gate.
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
    "Prefer the Android app? It's still in closed testing — join our " +
    "testers group, then install it from Google Play. The browser " +
    "version above needs none of this.",
};
