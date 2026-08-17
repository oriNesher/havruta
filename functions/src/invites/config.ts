// Firebase Hosting auto-provisions this domain for project "havruta-app" —
// no custom domain purchase needed. Override via the INVITE_LINK_BASE_URL
// env var (e.g. functions config / .env) if a custom domain is added later.
export const INVITE_LINK_BASE_URL =
  process.env.INVITE_LINK_BASE_URL ?? "https://havruta-app.web.app";

// Must match android/app/build.gradle.kts applicationId and the
// package_name in web/.well-known/assetlinks.json.
export const ANDROID_PACKAGE_NAME = "com.orinesher.havruta";

/**
 * @param {string} linkId The invite link's document id.
 * @return {string} The full shareable invite URL for this link.
 */
export function buildInviteUrl(linkId: string): string {
  return `${INVITE_LINK_BASE_URL}/i/${linkId}`;
}

/**
 * Builds an Android `intent://` URI for the given invite link. Unlike a
 * plain https href, this forces Chrome to re-resolve the link as an
 * external intent even when tapped from inside a tab already showing
 * the same origin (the "Open in app" button lives on the very page this
 * URL points to) — a plain same-URL href would otherwise just reload
 * the current page instead of handing off to the app. Falls back to the
 * normal https landing page if no app is registered to handle it.
 * @param {string} linkId The invite link's document id.
 * @return {string} An Android intent:// URI.
 */
export function buildAndroidIntentUrl(linkId: string): string {
  const httpsUrl = buildInviteUrl(linkId);
  const host = new URL(httpsUrl).host;
  const fallback = encodeURIComponent(httpsUrl);
  return `intent://${host}/i/${linkId}#Intent;scheme=https;` +
    `package=${ANDROID_PACKAGE_NAME};` +
    `S.browser_fallback_url=${fallback};end`;
}
