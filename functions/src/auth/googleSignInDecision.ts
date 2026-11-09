/**
 * Pure decision logic for googleSignInPreflight, kept free of Firebase so it
 * can be unit tested directly.
 *
 * Why this exists: with "one account per email", Firebase treats Google as
 * authoritative for its addresses. Signing in with Google to an email that
 * already belongs to an account whose email is NOT verified keeps the uid
 * but deletes that account's password (and any other linked provider) —
 * reproduced in the Auth emulator. Havruta has never sent verification
 * emails, so every existing email/password user is in that state. The
 * preflight catches the case before the Firebase sign-in happens, so the
 * client can have the user sign in the usual way and *link* Google instead,
 * which keeps every existing credential.
 */

export interface ExistingAccount {
  emailVerified: boolean;
  providers: {providerId: string; uid: string}[];
}

export type GoogleSignInDecision =
  | {action: "proceed"}
  | {action: "linkRequired"; methods: string[]};

/**
 * @param {ExistingAccount | null} existing The account already registered
 *   under the Google account's email, or null if there is none.
 * @param {string} googleSub The Google account's stable id (`sub` claim).
 * @return {GoogleSignInDecision} Whether a plain Google sign-in is safe, or
 *   the existing sign-in methods the user must use first to link Google.
 */
export function decideGoogleSignIn(
  existing: ExistingAccount | null,
  googleSub: string
): GoogleSignInDecision {
  if (!existing) return {action: "proceed"};

  const alreadyLinked = existing.providers.some(
    (p) => p.providerId === "google.com" && p.uid === googleSub
  );
  if (alreadyLinked) return {action: "proceed"};

  // A verified email makes Firebase link Google and keep the existing
  // credentials, so nothing is lost.
  if (existing.emailVerified) return {action: "proceed"};

  const methods = existing.providers
    .map((p) => p.providerId)
    .filter((id) => id !== "google.com");
  // No sign-in method to lose (e.g. an admin-created shell account).
  if (methods.length === 0) return {action: "proceed"};

  return {action: "linkRequired", methods};
}
