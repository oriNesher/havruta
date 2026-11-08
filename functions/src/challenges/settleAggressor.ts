import {randomUUID} from "crypto";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {EventDraft} from "../events/types";
import {newEventFields} from "../events/persist";
import {
  AggressorCause,
  detectAggressorTakeoverEvents,
} from "../events/rules/aggressorTakeover";
import {aggressorApplies, aggressorWindow, decideAggressor} from "./aggressor";
import {ChallengeConfig, parseChallenge} from "./model";
import {StandingParticipant, toStandingParticipant} from "./standings";

/** What one badge re-evaluation decided to write. */
export interface AggressorPlan {
  /**
   * The new competition.aggressor fields (since aside), or null when
   * nothing changed and today was already evaluated — no write at all.
   */
  state: {
    uid: string | null;
    username: string | null;
    transferCount: number;
    evaluatedDay: string;
    holderChanged: boolean;
  } | null;
  /** The takeover event to create alongside, if the badge changed hands. */
  drafts: EventDraft[];
}

const NO_CHANGE: AggressorPlan = {state: null, drafts: []};

/**
 * Re-decides the badge and works out what to write. Pure, so the settling
 * transaction and tests share it. Writes only when the holder changes or
 * on the first evaluation of a new challenge day (which records the day,
 * so the hourly rollover pass knows it's been done).
 * @param {object} input Everything the decision needs.
 * @param {string} input.competitionTitle The challenge's title.
 * @param {ChallengeConfig} input.challenge The challenge.
 * @param {boolean} input.isOnboarding Whether it's an onboarding challenge.
 * @param {StandingParticipant[]} input.participants Everyone in it.
 * @param {AggressorCause} input.cause What prompted this re-evaluation.
 * @param {string | null} input.reporterUid Whose progress write prompted
 *   it, if one did.
 * @param {number} input.nowMillis The current time.
 * @return {AggressorPlan} What to write.
 */
export function planAggressor(input: {
  competitionTitle: string;
  challenge: ChallengeConfig;
  isOnboarding: boolean;
  participants: StandingParticipant[];
  cause: AggressorCause;
  reporterUid: string | null;
  nowMillis: number;
}): AggressorPlan {
  const {challenge, participants, nowMillis} = input;
  if (!aggressorApplies(challenge, input.isOnboarding)) return NO_CHANGE;

  const current = challenge.aggressor;
  const windowDays = aggressorWindow(challenge, nowMillis);
  const today = windowDays[0];
  const {holderUid, scores} =
    decideAggressor(challenge, participants, current.uid, nowMillis);
  const holderChanged = holderUid !== current.uid;

  if (!holderChanged && current.evaluatedDay === today) return NO_CHANGE;

  return {
    state: {
      uid: holderUid,
      username: holderUid === null ?
        null :
        participants.find((p) => p.uid === holderUid)?.username ?? null,
      transferCount: current.transferCount + (holderChanged ? 1 : 0),
      evaluatedDay: today,
      holderChanged,
    },
    drafts: detectAggressorTakeoverEvents({
      competitionTitle: input.competitionTitle,
      participants: participants.map((p) => ({
        uid: p.uid,
        username: p.username,
      })),
      previousHolderUid: current.uid,
      previousHolderUsername: current.username,
      newHolderUid: holderUid,
      cause: input.cause,
      reporterUid: input.reporterUid,
      scores,
      windowDays,
    }),
  };
}

/**
 * Plans from a competition doc and its participants, as read.
 * @param {FirebaseFirestore.DocumentData} data The competition doc's data.
 * @param {FirebaseFirestore.QuerySnapshot} participantsSnap Its
 *   participants.
 * @param {AggressorCause} cause What prompted this re-evaluation.
 * @param {string | null} reporterUid Whose progress write prompted it.
 * @param {number} nowMillis The current time.
 * @return {object} The parsed inputs and the plan.
 */
function planFromDocs(
  data: FirebaseFirestore.DocumentData,
  participantsSnap: FirebaseFirestore.QuerySnapshot,
  cause: AggressorCause,
  reporterUid: string | null,
  nowMillis: number
): {
  challenge: ChallengeConfig;
  isOnboarding: boolean;
  participants: StandingParticipant[];
  plan: AggressorPlan;
} {
  const challenge = parseChallenge(data);
  const isOnboarding = data.onboarding?.isOnboarding === true;
  const participants = participantsSnap.docs
    .map((doc) => toStandingParticipant(doc.data(), challenge))
    .filter((p) => !!p.uid);
  const plan = planAggressor({
    competitionTitle: data.title ?? "Challenge",
    challenge,
    isOnboarding,
    participants,
    cause,
    reporterUid,
    nowMillis,
  });
  return {challenge, isOnboarding, participants, plan};
}

/**
 * Re-decides one challenge's Aggressor Badge and, if it changed hands,
 * records the new holder and creates the takeover event — both in one
 * transaction, so every real transfer produces exactly one event and a
 * retried or overlapping run (concurrent progress triggers, the hourly
 * pass) produces none. The event's doc id is keyed on the transfer count
 * as a second guard: a duplicate create fails rather than doubling up.
 *
 * A plain read first skips the transaction (and its locks on every
 * participant doc) in the common case where nothing changes. That's safe:
 * the trigger for the latest progress write always reads after every
 * earlier write landed, so the final state is never skipped.
 * @param {string} competitionId The challenge.
 * @param {AggressorCause} cause What prompted this re-evaluation.
 * @param {string | null} reporterUid Whose progress write prompted it.
 * @param {string} batchId Shared with the other events from the same
 *   progress update, so they celebrate on one screen.
 * @return {Promise<void>} Resolves once settled.
 */
export async function settleAggressor(
  competitionId: string,
  cause: AggressorCause,
  reporterUid: string | null,
  batchId: string = randomUUID()
): Promise<void> {
  const db = admin.firestore();
  const ref = db.collection("competitions").doc(competitionId);

  const [snap, participantsSnap] = await Promise.all([
    ref.get(),
    ref.collection("participants").get(),
  ]);
  if (!snap.exists) return;
  const nowMillis = admin.firestore.Timestamp.now().toMillis();
  const {challenge, isOnboarding, participants, plan} = planFromDocs(
    snap.data() ?? {}, participantsSnap, cause, reporterUid, nowMillis);

  // Every evaluation, including "nothing changed", so a report that didn't
  // move the badge can be explained from the logs alone.
  const decision = decideAggressor(
    challenge, participants, challenge.aggressor.uid, nowMillis);
  logger.info("Aggressor Badge evaluated", {
    competitionId,
    cause,
    reporterUid,
    applies: aggressorApplies(challenge, isOnboarding),
    status: challenge.status,
    isLegacyPersonal: challenge.isLegacyPersonal,
    isOnboarding,
    participantCount: participants.length,
    window: aggressorWindow(challenge, nowMillis),
    scores: decision.scores.map((score) => ({
      uid: score.uid,
      windowTotal: score.windowTotal,
      eligibleDays: score.eligibleDays,
    })),
    holderBefore: challenge.aggressor.uid,
    holderAfter: decision.holderUid,
    willWrite: plan.state !== null,
  });

  if (!plan.state) return;

  const written = await db.runTransaction(async (tx) => {
    const txSnap = await tx.get(ref);
    if (!txSnap.exists) return null;
    const txParticipants = await tx.get(ref.collection("participants"));
    const {challenge, plan} = planFromDocs(txSnap.data() ?? {},
      txParticipants, cause, reporterUid,
      admin.firestore.Timestamp.now().toMillis());
    const state = plan.state;
    if (!state) return null;

    tx.update(ref, {
      aggressor: {
        uid: state.uid,
        username: state.username,
        since: state.holderChanged ?
          admin.firestore.FieldValue.serverTimestamp() :
          challenge.aggressor.since,
        transferCount: state.transferCount,
        evaluatedDay: state.evaluatedDay,
      },
    });
    for (const draft of plan.drafts) {
      tx.create(
        ref.collection("events").doc(
          `aggressorTakeover-${state.transferCount}`),
        newEventFields(competitionId, draft, batchId)
      );
    }

    return {from: challenge.aggressor.uid, state, events: plan.drafts.length};
  });

  if (written?.state.holderChanged) {
    logger.info("Aggressor Badge changed hands", {
      competitionId,
      cause,
      from: written.from,
      to: written.state.uid,
      transferCount: written.state.transferCount,
      events: written.events,
    });
  }
}
