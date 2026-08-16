// Firebase Hosting auto-provisions this domain for project "havruta-app" —
// no custom domain purchase needed. Override via the INVITE_LINK_BASE_URL
// env var (e.g. functions config / .env) if a custom domain is added later.
export const INVITE_LINK_BASE_URL =
  process.env.INVITE_LINK_BASE_URL ?? "https://havruta-app.web.app";

/**
 * @param {string} linkId The invite link's document id.
 * @return {string} The full shareable invite URL for this link.
 */
export function buildInviteUrl(linkId: string): string {
  return `${INVITE_LINK_BASE_URL}/i/${linkId}`;
}
