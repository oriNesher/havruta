import * as assert from "node:assert/strict";
import {test} from "node:test";
import {
  ANDROID_PACKAGE_NAME,
  buildAndroidIntentUrl,
  buildInviteUrl,
  buildWebAppInviteUrl,
} from "../config";

test("buildInviteUrl points at the /i/ landing page", () => {
  assert.equal(
    buildInviteUrl("abc123"),
    "https://havruta-app.web.app/i/abc123"
  );
});

test("buildWebAppInviteUrl points at /join/, not /i/", () => {
  assert.equal(
    buildWebAppInviteUrl("abc123"),
    "https://havruta-app.web.app/join/abc123"
  );
});

// The whole reason buildWebAppInviteUrl exists: Hosting rewrites /i/** to
// the inviteLanding function, so a web-app link on that path could never
// reach the Flutter app. If these two ever collide, the "Open in browser"
// button silently becomes a link back to the landing page itself.
test("the web-app and landing-page paths never collide", () => {
  const landing = new URL(buildInviteUrl("abc123"));
  const webApp = new URL(buildWebAppInviteUrl("abc123"));
  assert.notEqual(landing.pathname, webApp.pathname);
  assert.ok(!webApp.pathname.startsWith("/i/"));
});

test("buildAndroidIntentUrl targets the app package with an https fallback",
  () => {
    const url = buildAndroidIntentUrl("abc123");
    assert.ok(url.startsWith("intent://havruta-app.web.app/i/abc123"));
    assert.ok(url.includes(`package=${ANDROID_PACKAGE_NAME}`));
    assert.ok(
      url.includes(
        "S.browser_fallback_url=" +
        encodeURIComponent("https://havruta-app.web.app/i/abc123")
      )
    );
  });
