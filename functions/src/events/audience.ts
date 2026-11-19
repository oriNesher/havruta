// Who an event reaches. In a small (friend) challenge that's everyone but
// the actor — the original behavior. In a large one, events go to the
// people they matter to, so a 200-person challenge isn't 199 cards per
// report:
// - "everyone": headline news — a win or podium finish, a new leader,
//   first blood, the race tightening at the top.
// - "nearby": the actor's leaderboard neighbors (±NEIGHBOR_RADIUS places),
//   their followers and their teammates — progress, streaks, milestones,
//   eliminations.
// - "social": followers and teammates only — joins and leaves.
// Events addressed to one person (overtook you, closing in on you) don't
// go through here at all.
import {ChallengeConfig, isLargeChallenge} from "../challenges/model";
import {rankStandings, toStandingParticipant} from "../challenges/standings";

export type AudienceTier = "everyone" | "nearby" | "social";

/** Places either side of the actor that count as "nearby". */
export const NEIGHBOR_RADIUS = 3;

/** Everything needed to address events in a large challenge. */
export interface Audience {
  /** Participant uids, leader first. */
  rankedUids: string[];
  /** Who follows whom: follower uid → the uids they follow. */
  followingByUid: Record<string, string[]>;
  /** Each participant's team, if any. */
  teamOf: Record<string, string | null>;
}

/**
 * Builds a large challenge's audience from its participant docs and follow
 * docs; null for a small challenge (everyone hears everything). Pure.
 * @param {ChallengeConfig} challenge The challenge.
 * @param {FirebaseFirestore.DocumentData[]} participantDocs Its
 *   participants/{uid} docs' data.
 * @param {Record<string, string[]>} followingByUid follows/{uid} docs, as
 *   follower → followed uids (may cover only the followers that matter).
 * @return {Audience | null} The audience, or null when small.
 */
export function buildAudience(
  challenge: ChallengeConfig,
  participantDocs: FirebaseFirestore.DocumentData[],
  followingByUid: Record<string, string[]>
): Audience | null {
  if (!isLargeChallenge(challenge)) return null;
  const standings = participantDocs
    .map((data) => toStandingParticipant(data, challenge))
    .filter((p) => !!p.uid);
  return {
    rankedUids: rankStandings(challenge, standings).map((p) => p.uid),
    followingByUid,
    teamOf: Object.fromEntries(participantDocs
      .filter((data) => typeof data.uid === "string")
      .map((data) => [
        data.uid,
        typeof data.teamId === "string" && data.teamId ? data.teamId : null,
      ])),
  };
}

/**
 * The recipients of an event about `actorUid`. Never includes the actor.
 * @param {Audience | null | undefined} audience The large-challenge
 *   audience, or null/undefined for a small challenge.
 * @param {string[]} everyone Every member who could receive it.
 * @param {string} actorUid Whom the event is about.
 * @param {AudienceTier} tier How widely it should travel.
 * @return {string[]} The recipients.
 */
export function audienceFor(
  audience: Audience | null | undefined,
  everyone: string[],
  actorUid: string,
  tier: AudienceTier
): string[] {
  const others = [...new Set(everyone)].filter((uid) => uid !== actorUid);
  if (!audience || tier === "everyone") return others;

  const reach = new Set<string>();
  for (const [follower, following] of
    Object.entries(audience.followingByUid)) {
    if (following.includes(actorUid)) reach.add(follower);
  }
  const team = audience.teamOf[actorUid] ?? null;
  if (team !== null) {
    for (const [uid, teamId] of Object.entries(audience.teamOf)) {
      if (teamId === team) reach.add(uid);
    }
  }
  if (tier === "nearby") {
    const index = audience.rankedUids.indexOf(actorUid);
    if (index !== -1) {
      audience.rankedUids
        .slice(
          Math.max(0, index - NEIGHBOR_RADIUS),
          index + NEIGHBOR_RADIUS + 1
        )
        .forEach((uid) => reach.add(uid));
    }
  }
  return others.filter((uid) => reach.has(uid));
}

/**
 * Follow docs as follower → followed uids.
 * @param {FirebaseFirestore.QueryDocumentSnapshot[]} docs follows/{uid}.
 * @return {Record<string, string[]>} The mapping.
 */
export function followingFromDocs(
  docs: FirebaseFirestore.QueryDocumentSnapshot[]
): Record<string, string[]> {
  return Object.fromEntries(docs.map((doc) => {
    const following = doc.data().followingUids;
    return [
      doc.id,
      Array.isArray(following) ?
        following.filter((u): u is string => typeof u === "string") :
        [],
    ];
  }));
}
