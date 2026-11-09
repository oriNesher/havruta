import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {OAuth2Client} from "google-auth-library";
import {GOOGLE_OAUTH_CLIENT_IDS} from "./config";
import {ExistingAccount, decideGoogleSignIn} from "./googleSignInDecision";

const oauthClient = new OAuth2Client();

/**
 * Called by the client between "Google account chosen" and "Firebase
 * sign-in", to find out whether a plain Google sign-in would strip an
 * existing account's password (see googleSignInDecision.ts).
 *
 * Unauthenticated by design — the caller isn't signed in yet. It still
 * can't be used to probe which emails are registered: the caller must
 * present a Google ID token issued to this app, so it only ever learns
 * about the email it has just proven it owns.
 */
export const googleSignInPreflight = onCall(
  {maxInstances: 5},
  async (request) => {
    const idToken = request.data?.idToken;
    if (typeof idToken !== "string" || !idToken) {
      throw new HttpsError("invalid-argument", "idToken is required.");
    }
    if (GOOGLE_OAUTH_CLIENT_IDS.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "Google sign-in is not configured."
      );
    }

    let payload;
    try {
      const ticket = await oauthClient.verifyIdToken({
        idToken,
        audience: GOOGLE_OAUTH_CLIENT_IDS,
      });
      payload = ticket.getPayload();
    } catch (e) {
      logger.warn("Google ID token rejected", {error: String(e)});
      throw new HttpsError("invalid-argument", "Invalid Google ID token.");
    }

    // Without a verified email Firebase never matches an existing account
    // by email, so there's nothing it could overwrite.
    if (!payload?.sub || !payload.email || !payload.email_verified) {
      return {action: "proceed"};
    }

    let existing: ExistingAccount | null = null;
    try {
      const user = await admin.auth().getUserByEmail(payload.email);
      existing = {
        emailVerified: user.emailVerified,
        providers: user.providerData.map((p) => ({
          providerId: p.providerId,
          uid: p.uid,
        })),
      };
    } catch (e) {
      if ((e as {code?: string}).code !== "auth/user-not-found") throw e;
    }

    const decision = decideGoogleSignIn(existing, payload.sub);
    logger.info("Google sign-in preflight", {action: decision.action});
    return decision;
  }
);
