import {
  ChallengeConfig,
  isLargeChallenge,
  parseChallenge,
} from "../challenges/model";
import {Audience, buildAudience, followingFromDocs} from "./audience";

/**
 * Loads a large challenge's audience (see buildAudience); null for a small
 * one, without reading anything. With an actor, only that actor's
 * followers are read (one array-contains query); without one (end-of-day
 * jobs announcing many people), every follow doc.
 * @param {FirebaseFirestore.DocumentReference} competitionRef The challenge.
 * @param {ChallengeConfig} challenge Its parsed definition.
 * @param {FirebaseFirestore.DocumentData[]} participantDocs Its
 *   participants' doc data.
 * @param {string | null} actorUid The one actor, if there's one.
 * @return {Promise<Audience | null>} The audience, or null when small.
 */
export async function loadAudience(
  competitionRef: FirebaseFirestore.DocumentReference,
  challenge: ChallengeConfig,
  participantDocs: FirebaseFirestore.DocumentData[],
  actorUid: string | null
): Promise<Audience | null> {
  if (!isLargeChallenge(challenge)) return null;
  const follows = competitionRef.collection("follows");
  const snap = actorUid ?
    await follows.where("followingUids", "array-contains", actorUid).get() :
    await follows.get();
  return buildAudience(
    challenge, participantDocs, followingFromDocs(snap.docs));
}

/**
 * Re-reads a challenge and everything its audience needs — for jobs that
 * announce outcomes after their transaction committed (so the ranking
 * reflects what was just written).
 * @param {FirebaseFirestore.DocumentReference} competitionRef The challenge.
 * @return {Promise<Audience | null>} The audience, or null when small.
 */
export async function loadAudienceFor(
  competitionRef: FirebaseFirestore.DocumentReference
): Promise<Audience | null> {
  const [snap, participants] = await Promise.all([
    competitionRef.get(),
    competitionRef.collection("participants").get(),
  ]);
  if (!snap.exists) return null;
  return loadAudience(
    competitionRef,
    parseChallenge(snap.data() ?? {}),
    participants.docs.map((doc) => doc.data()),
    null
  );
}
