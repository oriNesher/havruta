import * as assert from "node:assert/strict";
import {test} from "node:test";
import {ChallengeConfig, parseChallenge} from "../model";
import {StandingParticipant} from "../standings";
import {AggressorPlan, planAggressor} from "../settleAggressor";
import {AggressorCause} from "../../events/rules/aggressorTakeover";

const HOUR = 60 * 60 * 1000;

/** "Now" for every test: noon UTC on 2026-10-10. */
const NOW = Date.UTC(2026, 9, 10) + 12 * HOUR;

/**
 * A Most Progress challenge whose badge Alice holds, decided today.
 * @param {object} overrides Raw competition fields to override.
 * @return {ChallengeConfig} The parsed challenge.
 */
function challenge(overrides: Record<string, unknown> = {}): ChallengeConfig {
  return parseChallenge({
    winCondition: "mostProgress",
    status: "active",
    aggressor: {
      uid: "alice",
      username: "Alice",
      transferCount: 4,
      evaluatedDay: "2026-10-10",
    },
    ...overrides,
  });
}

/**
 * A participant fixture.
 * @param {string} uid Their uid.
 * @param {number} today What they've logged today.
 * @return {StandingParticipant} The participant.
 */
function participant(uid: string, today: number): StandingParticipant {
  return {
    uid,
    username: uid[0].toUpperCase() + uid.slice(1),
    progress: today,
    targetValue: null,
    dailyProgress: {"2026-10-10": today},
    eliminatedOnDay: null,
    joinedDay: "2026-10-01",
    updatedAtMillis: NOW - HOUR,
  };
}

/**
 * Plans with sensible defaults.
 * @param {ChallengeConfig} config The challenge.
 * @param {StandingParticipant[]} participants Everyone in it.
 * @param {object} options Overrides.
 * @param {AggressorCause} options.cause The cause; default progress.
 * @param {string | null} options.reporterUid The reporter; default bob.
 * @param {boolean} options.isOnboarding Default false.
 * @return {AggressorPlan} The plan.
 */
function plan(
  config: ChallengeConfig,
  participants: StandingParticipant[],
  options: {
    cause?: AggressorCause;
    reporterUid?: string | null;
    isOnboarding?: boolean;
  } = {}
): AggressorPlan {
  return planAggressor({
    competitionTitle: "Pushups",
    challenge: config,
    isOnboarding: options.isOnboarding ?? false,
    participants,
    cause: options.cause ?? "progress",
    reporterUid: options.reporterUid === undefined ?
      "bob" :
      options.reporterUid,
    nowMillis: NOW,
  });
}

test("no write when the holder stays and today was already decided", () => {
  const result = plan(challenge(), [
    participant("alice", 10),
    participant("bob", 5),
  ]);
  assert.deepEqual(result, {state: null, drafts: []});
});

test("a new day is recorded even when the holder stays", () => {
  const result = plan(
    challenge({aggressor: {uid: "alice", evaluatedDay: "2026-10-09"}}),
    [participant("alice", 10), participant("bob", 5)],
    {cause: "dayRollover", reporterUid: null}
  );
  assert.equal(result.state?.evaluatedDay, "2026-10-10");
  assert.equal(result.state?.holderChanged, false);
  assert.equal(result.state?.transferCount, 0);
  assert.deepEqual(result.drafts, []);
});

test("a transfer records the new holder and one takeover", () => {
  const result = plan(challenge(), [
    participant("alice", 10),
    participant("bob", 11),
  ]);
  assert.deepEqual(result.state, {
    uid: "bob",
    username: "Bob",
    transferCount: 5,
    evaluatedDay: "2026-10-10",
    holderChanged: true,
  });
  assert.equal(result.drafts.length, 1);
  assert.equal(result.drafts[0].payload.actorUid, "bob");
  assert.equal(result.drafts[0].payload.targetUid, "alice");
  assert.equal(result.drafts[0].payload.actorCelebrated, false);
});

test("going vacant is recorded without a takeover", () => {
  const result = plan(
    challenge({aggressor: {uid: "alice", evaluatedDay: "2026-10-09"}}),
    [participant("alice", 0), participant("bob", 0)],
    {cause: "dayRollover", reporterUid: null}
  );
  assert.equal(result.state?.uid, null);
  assert.equal(result.state?.username, null);
  assert.equal(result.state?.holderChanged, true);
  assert.deepEqual(result.drafts, []);
});

test("a first claim counts as a transfer", () => {
  const result = plan(
    challenge({aggressor: undefined}),
    [participant("alice", 0), participant("bob", 3)]
  );
  assert.equal(result.state?.uid, "bob");
  assert.equal(result.state?.transferCount, 1);
  assert.equal(result.drafts[0].payload.targetUid, null);
});

test("a completed challenge keeps its final holder", () => {
  const result = plan(challenge({status: "completed"}), [
    participant("alice", 1),
    participant("bob", 50),
  ]);
  assert.deepEqual(result, {state: null, drafts: []});
});

test("onboarding challenges have no badge", () => {
  const result = plan(
    challenge({aggressor: undefined}),
    [participant("alice", 1), participant("bob", 50)],
    {isOnboarding: true}
  );
  assert.deepEqual(result, {state: null, drafts: []});
});

test("parseChallenge reads the badge state, defaulting to vacant", () => {
  assert.deepEqual(parseChallenge({}).aggressor, {
    uid: null,
    username: null,
    since: null,
    transferCount: 0,
    evaluatedDay: null,
  });
  const parsed = challenge().aggressor;
  assert.equal(parsed.uid, "alice");
  assert.equal(parsed.username, "Alice");
  assert.equal(parsed.transferCount, 4);
  assert.equal(parsed.evaluatedDay, "2026-10-10");
});
