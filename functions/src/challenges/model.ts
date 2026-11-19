// The one place a competitions/{id} document is interpreted as a challenge
// definition. Everything downstream (event rules, invites, the end-of-
// challenge jobs) reads a ChallengeConfig instead of the raw `type` /
// `shared*` fields, so legacy documents and new ones look the same past
// this point. Mirrored by hand on the client in
// lib/competitions/challenge.dart — keep the two in sync.

/**
 * How a challenge's winner is decided. Stored as competition.winCondition;
 * a document without one predates win conditions and is a race.
 */
export const WIN_CONDITIONS = [
  "firstToTarget",
  "lastStanding",
  "mostProgress",
] as const;

export type WinCondition = typeof WIN_CONDITIONS[number];

/** Extra constraints layered on top of the win condition. */
export interface ChallengeRules {
  /**
   * Minimum progress per challenge day. Required for lastStanding; null
   * when the challenge has no daily requirement.
   */
  dailyMinimum: number | null;
  /**
   * Missed days a participant can absorb before elimination. Reserved for
   * grace days — always 0 until that rule is implemented.
   */
  lives: number;
}

/**
 * Who holds the Aggressor Badge, as last decided by settleAggressor. Only
 * the server writes it; it stays as it was once the challenge completes,
 * which is what makes the last holder the "Final Aggressor".
 */
export interface AggressorState {
  /** The holder; null while the badge is vacant. */
  uid: string | null;
  username: string | null;
  /** When the current holder took it. */
  since: FirebaseFirestore.Timestamp | null;
  /** Times the holder has changed; keys each takeover event's doc id. */
  transferCount: number;
  /** The challenge day (YYYY-MM-DD) the badge was last decided on. */
  evaluatedDay: string | null;
}

export interface ChallengeConfig {
  /** The creator's uid; null only on malformed documents. */
  createdBy: string | null;
  /** Everyone competing. */
  participantUids: string[];
  /**
   * Who runs the challenge. A document without organizerUids predates the
   * organizer role and is run by its creator alone — the same fallback
   * firestore.rules (organizersOf) applies.
   */
  organizerUids: string[];
  winCondition: WinCondition;
  /**
   * A pre-redesign personalGoalChallenge: still a race, but each
   * participant races to their own participants/{uid}.targetValue.
   */
  isLegacyPersonal: boolean;
  goalTitle: string;
  unit: string;
  /** The finish line for firstToTarget; null for the other modes. */
  targetValue: number | null;
  rules: ChallengeRules;
  /** IANA zone whose calendar defines challenge days; null means UTC. */
  timeZone: string | null;
  startsAt: FirebaseFirestore.Timestamp | null;
  endsAt: FirebaseFirestore.Timestamp | null;
  status: string;
  winnerUids: string[];
  /** Finish order for firstToTarget, earliest first. */
  finisherUids: string[];
  /**
   * Finishers a race had before finisherUids was recorded, frozen at the
   * first claim; null until then. See claimFinish.
   */
  legacyFinisherCount: number | null;
  /** Last challenge day the lastStanding evaluator has judged. */
  lastEvaluatedDay: string | null;
  /**
   * Participants when lastStanding judging began; with fewer than 2 there
   * is nobody to outlast, so no winner is declared. Null until then.
   */
  startingParticipantCount: number | null;
  aggressor: AggressorState;
}

/**
 * Whether a value is a known win condition.
 * @param {unknown} value A raw competition.winCondition value.
 * @return {boolean} True for one of WIN_CONDITIONS.
 */
export function isWinCondition(value: unknown): value is WinCondition {
  return (WIN_CONDITIONS as readonly unknown[]).includes(value);
}

/**
 * Whether a user takes part in a challenge — competing or organizing.
 * Mirrors isMemberOf in firestore.rules.
 * @param {ChallengeConfig} challenge The challenge.
 * @param {string} uid The user.
 * @return {boolean} True for a participant or an organizer.
 */
export function isChallengeMember(
  challenge: ChallengeConfig,
  uid: string
): boolean {
  return challenge.participantUids.includes(uid) ||
    challenge.organizerUids.includes(uid);
}

/**
 * Returns a positive number, or null for anything else.
 * @param {unknown} value A raw document value.
 * @return {number | null} The value if it's a positive number.
 */
function positiveNumberOrNull(value: unknown): number | null {
  return typeof value === "number" && value > 0 ? value : null;
}

/**
 * Returns a Firestore Timestamp, or null for anything else.
 * @param {unknown} value A raw document value.
 * @return {FirebaseFirestore.Timestamp | null} The timestamp, if it is one.
 */
function timestampOrNull(value: unknown): FirebaseFirestore.Timestamp | null {
  const candidate = value as FirebaseFirestore.Timestamp | null | undefined;
  return candidate && typeof candidate.toMillis === "function" ?
    candidate :
    null;
}

/**
 * Returns the string entries of an array, or [] for anything else.
 * @param {unknown} value A raw document value.
 * @return {string[]} The array's strings.
 */
function stringArray(value: unknown): string[] {
  return Array.isArray(value) ?
    value.filter((entry): entry is string => typeof entry === "string") :
    [];
}

/**
 * Normalizes a competitions/{id} document into a ChallengeConfig. Never
 * throws: unknown or missing fields fall back to the pre-redesign race.
 * @param {FirebaseFirestore.DocumentData} data The competition doc's data.
 * @return {ChallengeConfig} The normalized challenge definition.
 */
export function parseChallenge(
  data: FirebaseFirestore.DocumentData
): ChallengeConfig {
  const winCondition = isWinCondition(data.winCondition) ?
    data.winCondition :
    "firstToTarget";
  // Only documents written before win conditions existed can be personal:
  // new challenges always carry a winCondition.
  const isLegacyPersonal = data.winCondition === undefined &&
    data.type === "personalGoalChallenge";
  const rawRules = (data.rules ?? {}) as Record<string, unknown>;
  const winnerUids = stringArray(data.winnerUids);
  const legacyWinner = typeof data.winnerUid === "string" ?
    [data.winnerUid] :
    [];
  const rawAggressor = (data.aggressor ?? {}) as Record<string, unknown>;
  const createdBy = typeof data.createdBy === "string" && data.createdBy ?
    data.createdBy :
    null;

  return {
    createdBy,
    participantUids: stringArray(data.participantUids),
    organizerUids: Array.isArray(data.organizerUids) ?
      stringArray(data.organizerUids) :
      (createdBy ? [createdBy] : []),
    winCondition,
    isLegacyPersonal,
    goalTitle: typeof data.sharedGoalTitle === "string" ?
      data.sharedGoalTitle :
      "",
    unit: typeof data.sharedUnit === "string" ? data.sharedUnit : "",
    targetValue: winCondition === "firstToTarget" ?
      positiveNumberOrNull(data.sharedTargetValue) :
      null,
    rules: {
      dailyMinimum: positiveNumberOrNull(rawRules.dailyMinimum),
      lives: positiveNumberOrNull(rawRules.lives) ?? 0,
    },
    timeZone: typeof data.timeZone === "string" && data.timeZone ?
      data.timeZone :
      null,
    startsAt: timestampOrNull(data.startsAt),
    endsAt: timestampOrNull(data.endsAt),
    status: typeof data.status === "string" ? data.status : "active",
    winnerUids: winnerUids.length > 0 ? winnerUids : legacyWinner,
    finisherUids: stringArray(data.finisherUids),
    legacyFinisherCount: typeof data.legacyFinisherCount === "number" ?
      data.legacyFinisherCount :
      null,
    lastEvaluatedDay: typeof data.lastEvaluatedDay === "string" ?
      data.lastEvaluatedDay :
      null,
    startingParticipantCount:
      typeof data.startingParticipantCount === "number" ?
        data.startingParticipantCount :
        null,
    aggressor: {
      uid: typeof rawAggressor.uid === "string" ? rawAggressor.uid : null,
      username: typeof rawAggressor.username === "string" ?
        rawAggressor.username :
        null,
      since: timestampOrNull(rawAggressor.since),
      transferCount: typeof rawAggressor.transferCount === "number" ?
        rawAggressor.transferCount :
        0,
      evaluatedDay: typeof rawAggressor.evaluatedDay === "string" ?
        rawAggressor.evaluatedDay :
        null,
    },
  };
}
