import * as assert from "node:assert/strict";
import {test} from "node:test";
import {ChallengeConfig, parseChallenge} from "../model";
import {StandingParticipant} from "../standings";
import {
  aggressorApplies,
  aggressorWindow,
  decideAggressor,
} from "../aggressor";

const HOUR = 60 * 60 * 1000;

/**
 * A stand-in for a Firestore Timestamp.
 * @param {number} millis Epoch milliseconds.
 * @return {FirebaseFirestore.Timestamp} A timestamp-shaped object.
 */
function ts(millis: number): FirebaseFirestore.Timestamp {
  return {toMillis: () => millis} as FirebaseFirestore.Timestamp;
}

/** "Now" for every test: noon UTC on 2026-10-10. */
const NOW = Date.UTC(2026, 9, 10) + 12 * HOUR;

/**
 * A Most Progress challenge, overridable per test.
 * @param {object} overrides Raw competition fields to override.
 * @return {ChallengeConfig} The parsed challenge.
 */
function challenge(overrides: Record<string, unknown> = {}): ChallengeConfig {
  return parseChallenge({
    winCondition: "mostProgress",
    status: "active",
    ...overrides,
  });
}

/**
 * A participant fixture.
 * @param {string} uid Their uid.
 * @param {Record<string, number>} dailyProgress Their logged days.
 * @param {Partial<StandingParticipant>} overrides Fields to override.
 * @return {StandingParticipant} The participant.
 */
function participant(
  uid: string,
  dailyProgress: Record<string, number>,
  overrides: Partial<StandingParticipant> = {}
): StandingParticipant {
  return {
    uid,
    username: uid,
    progress: Object.values(dailyProgress).reduce((a, b) => a + b, 0),
    targetValue: null,
    dailyProgress,
    eliminatedOnDay: null,
    joinedDay: "2026-10-01",
    updatedAtMillis: NOW - HOUR,
    ...overrides,
  };
}

test("window is today and the two days before, newest first", () => {
  assert.deepEqual(aggressorWindow(challenge(), NOW), [
    "2026-10-10",
    "2026-10-09",
    "2026-10-08",
  ]);
});

test("window follows the challenge's time zone", () => {
  // 02:00 UTC on the 10th is still the 9th in New York.
  const early = Date.UTC(2026, 9, 10) + 2 * HOUR;
  const nyc = challenge({timeZone: "America/New_York"});
  assert.equal(aggressorWindow(nyc, early)[0], "2026-10-09");
});

test("most progress inside the window holds the badge", () => {
  const result = decideAggressor(challenge(), [
    participant("alice", {"2026-10-10": 5, "2026-10-08": 5}),
    participant("bob", {"2026-10-09": 12}),
  ], null, NOW);
  assert.equal(result.holderUid, "bob");
});

test("progress before the window doesn't count", () => {
  const result = decideAggressor(challenge(), [
    participant("alice", {"2026-10-07": 100, "2026-10-10": 1}),
    participant("bob", {"2026-10-10": 2}),
  ], null, NOW);
  assert.equal(result.holderUid, "bob");
  assert.equal(result.scores[0].windowTotal, 1);
});

test("a tie keeps the current holder", () => {
  const result = decideAggressor(challenge(), [
    participant("alice", {"2026-10-10": 10}, {updatedAtMillis: NOW - 2 * HOUR}),
    participant("bob", {"2026-10-10": 10}),
  ], "bob", NOW);
  assert.equal(result.holderUid, "bob");
});

test("a tie the holder isn't part of goes to whoever got there first", () => {
  const result = decideAggressor(challenge(), [
    participant("alice", {"2026-10-10": 5}),
    participant("bob", {"2026-10-10": 10}),
    participant("carol", {"2026-10-10": 10}, {updatedAtMillis: NOW - 3 * HOUR}),
  ], "alice", NOW);
  assert.equal(result.holderUid, "carol");
});

test("the badge passes as soon as someone edges ahead", () => {
  const result = decideAggressor(challenge(), [
    participant("alice", {"2026-10-10": 10}),
    participant("bob", {"2026-10-10": 11}),
  ], "alice", NOW);
  assert.equal(result.holderUid, "bob");
});

test("vacant when nobody has progress in the window", () => {
  const result = decideAggressor(challenge(), [
    participant("alice", {"2026-10-01": 50}),
    participant("bob", {}),
  ], "alice", NOW);
  assert.equal(result.holderUid, null);
});

test("vacant with fewer than 2 participants", () => {
  const result = decideAggressor(challenge(), [
    participant("alice", {"2026-10-10": 50}),
  ], null, NOW);
  assert.equal(result.holderUid, null);
});

test("a late joiner is scored per day they could compete", () => {
  // Bob joined today: 10 in 1 day beats Alice's 27 over 3 (9 a day).
  const result = decideAggressor(challenge(), [
    participant("alice", {
      "2026-10-08": 9, "2026-10-09": 9, "2026-10-10": 9,
    }),
    participant("bob", {"2026-10-10": 10}, {joinedDay: "2026-10-10"}),
  ], "alice", NOW);
  assert.equal(result.holderUid, "bob");
  assert.deepEqual(
    result.scores.map((s) => s.eligibleDays),
    [3, 1]
  );
});

test("equal rates across different day counts are a tie", () => {
  const result = decideAggressor(challenge(), [
    participant("alice", {
      "2026-10-08": 3, "2026-10-09": 3, "2026-10-10": 3,
    }),
    participant("bob", {"2026-10-10": 3}, {joinedDay: "2026-10-10"}),
  ], "alice", NOW);
  assert.equal(result.holderUid, "alice");
});

test("a joinedAt in the future still counts as one day", () => {
  const result = decideAggressor(challenge(), [
    participant("alice", {"2026-10-10": 5}),
    participant("bob", {"2026-10-10": 4}, {joinedDay: "2026-12-31"}),
  ], null, NOW);
  assert.equal(result.scores[1].eligibleDays, 1);
  assert.equal(result.scores[1].windowTotal, 0);
  assert.equal(result.holderUid, "alice");
});

test("days before the challenge started aren't counted", () => {
  const lastStanding = challenge({
    winCondition: "lastStanding",
    rules: {dailyMinimum: 5},
    startsAt: ts(Date.UTC(2026, 9, 10)),
  });
  const result = decideAggressor(lastStanding, [
    participant("alice", {"2026-10-10": 6}),
    participant("bob", {"2026-10-10": 5}),
  ], null, NOW);
  assert.deepEqual(result.scores.map((s) => s.eligibleDays), [1, 1]);
  assert.equal(result.holderUid, "alice");
});

test("eliminated participants can't hold the badge", () => {
  const result = decideAggressor(challenge({winCondition: "lastStanding"}), [
    participant("alice", {"2026-10-09": 50}, {eliminatedOnDay: "2026-10-09"}),
    participant("bob", {"2026-10-10": 5}),
  ], "alice", NOW);
  assert.equal(result.holderUid, "bob");
});

test("race finishers can hold the badge", () => {
  const race = challenge({
    winCondition: "firstToTarget",
    sharedTargetValue: 20,
  });
  const result = decideAggressor(race, [
    participant("alice", {"2026-10-10": 20}, {targetValue: 20}),
    participant("bob", {"2026-10-10": 8}, {targetValue: 20}),
  ], null, NOW);
  assert.equal(result.holderUid, "alice");
});

test("applies only to running, non-legacy, non-onboarding challenges", () => {
  assert.equal(aggressorApplies(challenge(), false), true);
  assert.equal(aggressorApplies(challenge(), true), false);
  assert.equal(
    aggressorApplies(challenge({status: "completed"}), false),
    false
  );
  assert.equal(
    aggressorApplies(parseChallenge({type: "personalGoalChallenge"}), false),
    false
  );
});
