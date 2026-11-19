// users/{uid} is private to its owner (it holds email, push tokens and the
// Respect wallet). What other users may see of someone — enough to find
// them by username and show their name — is mirrored server-side into
// publicProfiles/{uid}, which clients can read but never write.

/** The fields of publicProfiles/{uid}. */
export interface PublicProfile {
  uid: string;
  username: string;
  usernameLower: string;
}

/**
 * The public profile a users/{uid} document exposes, or null when it has
 * no username yet (e.g. a push token saved before registration finished)
 * and so shouldn't be findable.
 * @param {string} uid The user's id.
 * @param {FirebaseFirestore.DocumentData | undefined} data The users doc.
 * @return {PublicProfile | null} The profile to mirror, or null for none.
 */
export function publicProfileFor(
  uid: string,
  data: FirebaseFirestore.DocumentData | undefined
): PublicProfile | null {
  const username = typeof data?.username === "string" ?
    data.username.trim() :
    "";
  if (!username) return null;
  return {uid, username, usernameLower: username.toLowerCase()};
}
