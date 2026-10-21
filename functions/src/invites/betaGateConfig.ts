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
 */
export const BETA_GATE_CONFIG = {
  enabled: true,
  instructions:
    "Prefer the Android app? It's still in closed testing, so it takes " +
    "three quick steps — do all three with the same Google account your " +
    "phone's Play Store uses. The browser version above needs none of this.",
  // In order. Each `hint` names the exact button the tester will see on
  // the page the step opens, so the two must stay in sync with Google's UI.
  steps: [
    {
      label: "Join the Google Group",
      url: "https://groups.google.com/g/havruta-beta-testers",
      hint: "Tap “Join group”.",
    },
    {
      // The opt-in page, not the Store listing: in closed testing the
      // listing stays hidden until the tester taps "Become a tester" here,
      // and the Play Store app reports that as a misleading "No connection"
      // error.
      label: "Become a tester",
      url: "https://play.google.com/apps/testing/com.orinesher.havruta",
      hint: "Tap “Become a tester”.",
    },
    {
      label: "Download the app",
      url: "https://play.google.com/store/apps/details?id=com.orinesher.havruta",
      hint: "Tap “Install”.",
    },
  ],
};
