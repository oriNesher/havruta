import {onRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {lookupInvite} from "./lookup";
import {BETA_GATE_CONFIG} from "./betaGateConfig";
import {buildInviteUrl} from "./config";

/**
 * @param {string} value Untrusted text (e.g. a challenge title) to embed
 * in HTML.
 * @return {string} The value with HTML-special characters escaped.
 */
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * @param {{title: string, description: string, bodyHtml: string}} opts
 * Page content — bodyHtml must already be caller-escaped where needed.
 * @return {string} A complete HTML document.
 */
function renderPage(opts: {
  title: string;
  description: string;
  bodyHtml: string;
}): string {
  const title = escapeHtml(opts.title);
  const description = escapeHtml(opts.description);

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<meta property="og:title" content="${title}">
<meta property="og:description" content="${description}">
<meta name="description" content="${description}">
<style>
  body { font-family: -apple-system, system-ui, sans-serif; max-width: 480px;
    margin: 48px auto; padding: 0 20px; color: #1a1a2e; }
  .card { border: 1px solid #e2e2ea; border-radius: 16px; padding: 24px; }
  .btn { display: block; text-align: center; padding: 14px; border-radius: 12px;
    text-decoration: none; font-weight: 600; margin-top: 12px; }
  .btn-primary { background: #8B5CF6; color: #fff; }
  .btn-secondary { background: #f2f2f7; color: #1a1a2e; }
  .muted { color: #6b6b80; font-size: 14px; }
</style>
</head>
<body>
${opts.bodyHtml}
</body>
</html>`;
}

// GET /i/:linkId, routed here via a Firebase Hosting rewrite. Public,
// unauthenticated — this is what a recipient without the app sees, and
// what messaging apps scrape for link-preview cards (hence the OG tags).
export const inviteLanding = onRequest(
  {maxInstances: 10},
  async (req, res) => {
    const linkId = req.path.split("/").filter(Boolean).pop();

    if (!linkId) {
      res.status(404).send(renderPage({
        title: "Invite not found",
        description: "This invite link is missing its token.",
        bodyHtml:
          "<div class=\"card\"><p>This link looks incomplete.</p></div>",
      }));
      return;
    }

    const preview = await lookupInvite(linkId);
    const appLink = buildInviteUrl(linkId);

    if (!preview.valid) {
      const reasonText: Record<string, string> = {
        not_found: "This invite link doesn't exist.",
        revoked: "This invite link has been revoked by its creator.",
        expired: "This invite link has expired.",
        full: "This invite link has reached its limit.",
      };
      const message = reasonText[preview.reason ?? "not_found"] ??
        reasonText.not_found;

      res.status(200).send(renderPage({
        title: "Invite no longer available",
        description: message,
        bodyHtml: `<div class="card"><p>${escapeHtml(message)}</p></div>`,
      }));
      return;
    }

    const inviterName = preview.createdByUsername ?? "Someone";
    const challengeTitle = preview.competitionTitle ?? "a challenge";
    const description =
      `${inviterName} invited you to do "${challengeTitle}" ` +
      "together on Havruta.";

    let betaSectionHtml = "";
    if (BETA_GATE_CONFIG.enabled) {
      betaSectionHtml = `
        <p class="muted">${escapeHtml(BETA_GATE_CONFIG.instructions)}</p>
        <a class="btn btn-secondary" href="${BETA_GATE_CONFIG.googleGroupUrl}">
          1. Join the testers group
        </a>
        <a class="btn btn-secondary" href="${BETA_GATE_CONFIG.playListingUrl}">
          2. Install from Google Play
        </a>
        <p class="muted">Then tap this link again to jump back in.</p>
      `;
    }

    const bodyHtml = `
      <div class="card">
        <p class="muted">${escapeHtml(inviterName)} invited you to</p>
        <h1>${escapeHtml(challengeTitle)}</h1>
        <a class="btn btn-primary" href="${appLink}">Open in app</a>
        ${betaSectionHtml}
      </div>
    `;

    logger.info("Invite landing page served", {linkId});

    res.status(200).send(renderPage({
      title: `Join "${challengeTitle}" on Havruta`,
      description,
      bodyHtml,
    }));
  }
);
