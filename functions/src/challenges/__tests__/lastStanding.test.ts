import * as assert from "node:assert/strict";
import {test} from "node:test";
import {ChallengeConfig, parseChallenge} from "../model";
import {StandingParticipant} from "../standings";
import {evaluateLastStanding} from "../winConditions/lastStanding";

const HOUR = 60 * 60 * 1000;

/**
 * A stand-in for a Firestore Timestamp.
 * @param {number} millis Epoch milliseconds.
 * @return {FirebaseFirestore.Timestamp} A timestamp-shaped object.
 */
function ts(millis: number): FirebaseFirestore.Timestamp {
  return {toMillis: () => millis} as FirebaseFirestore.Timestamp;
}

/** Day 1 is 2026-10-05 (UTC challenge calendar). */
const DAY1_START = Date.UTC(2026, 9, 5);

/**
 * Noon UTC on challenge day [n].
 * @param {number} n The 1-based challenge day.
 * @return {number} Epoch millis.
 */
function noonOfDay(n: number): number {
  return DAY1_START + (n - 1) * 24 * HOUR + 12 * HOUR;
}

/**
 * A daily-30 Last One Standing challenge, overridable per test.
 * @param {object} overrides Raw competition fields to override.
 * @return {ChallengeConfig} The parsed challenge.
 */
function challenge(overrides: Record<string, unknown> = {}): ChallengeConfig {
  return parseChallenge({
    winCondition: "lastStanding",
    status: "active",
    rules: {dailyMinimum: 30},
    startsAt: ts(DAY1_START),
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
function player(
  uid: string,
  dailyProgress: Record<string, number>,
  overrides: Partial<StandingParticipant> = {}
): StandingParticipant {
  const progress = Object.values(dailyProgress).reduce((a, b) => a + b, 0);
  return {
    uid,
    username: uid,
    progress,
    targetValue: null,
    dailyProgress,
    eliminatedOnDay: null,
    joinedDay: "2026-10-04",
    updatedAtMillis: null,
    ...overrides,
  };
}

test("nothing is judged while day 1 is still running", () => {
  const result = evaluateLastStanding(
    challenge(),
    [player("a", {}), player("b", {})],
    noonOfDay(1)
  );

  assert.equal(result.update, null);
  assert.deepEqual(result.eliminations, []);
});

test("whoever missed the minimum is out; the rest carry on", () => {
  const result = evaluateLastStanding(
    challenge(),
    [
      player("a", {"2026-10-05": 30}),
      player("b", {"2026-10-05": 29}),
      player("c", {"2026-10-05": 45}),
    ],
    noonOfDay(2)
  );

  assert.deepEqual(result.eliminations, [
    {uid: "b", day: "2026-10-05", dayNumber: 1},
  ]);
  assert.equal(result.completes, false);
  assert.equal(result.update?.lastEvaluatedDay, "2026-10-05");
  assert.equal(result.update?.startingParticipantCount, 3);
});

test("the last one left wins", () => {
  const result = evaluateLastStanding(
    challenge(),
    [player("a", {"2026-10-05": 30}), player("b", {})],
    noonOfDay(2)
  );

  assert.equal(result.completes, true);
  assert.deepEqual(result.winnerUids, ["a"]);
  assert.equal(result.update?.status, "completed");
  assert.equal(result.update?.winnerUid, "a");
});

test("missed runs catch up day by day and stop at the decisive day", () => {
  const result = evaluateLastStanding(
    challenge({lastEvaluatedDay: "2026-10-04"}),
    [
      player("a", {"2026-10-05": 30, "2026-10-06": 30, "2026-10-07": 30}),
      player("b", {"2026-10-05": 30}),
      player("c", {"2026-10-05": 30, "2026-10-06": 30}),
    ],
    noonOfDay(5)
  );

  assert.deepEqual(
    result.eliminations.map((e) => [e.uid, e.dayNumber]),
    [["b", 2], ["c", 3]]
  );
  assert.deepEqual(result.winnerUids, ["a"]);
  assert.equal(result.update?.lastEvaluatedDay, "2026-10-07");
});

test("already-judged days are never judged again", () => {
  const result = evaluateLastStanding(
    challenge({lastEvaluatedDay: "2026-10-05", startingParticipantCount: 2}),
    [player("a", {"2026-10-06": 30}), player("b", {"2026-10-06": 30})],
    noonOfDay(2)
  );

  assert.equal(result.update, null);
});

test("everyone missing the same day: the closest that day wins", () => {
  const result = evaluateLastStanding(
    challenge(),
    [
      player("a", {"2026-10-05": 10}),
      player("b", {"2026-10-05": 20}),
      player("c", {}),
    ],
    noonOfDay(2)
  );

  assert.deepEqual(result.winnerUids, ["b"]);
  assert.deepEqual(result.eliminations.map((e) => e.uid), ["a", "c"]);
});

test("same-day tie on the day's progress falls back to total progress", () => {
  const result = evaluateLastStanding(
    challenge({lastEvaluatedDay: "2026-10-05"}),
    [
      player("a", {"2026-10-05": 30, "2026-10-06": 10}),
      player("b", {"2026-10-05": 50, "2026-10-06": 10}),
    ],
    noonOfDay(3)
  );

  assert.deepEqual(result.winnerUids, ["b"]);
});

test("a perfect tie shares the win", () => {
  const result = evaluateLastStanding(
    challenge(),
    [player("a", {"2026-10-05": 5}), player("b", {"2026-10-05": 5})],
    noonOfDay(2)
  );

  assert.deepEqual(result.winnerUids, ["a", "b"]);
  assert.deepEqual(result.eliminations, []);
  assert.equal(result.completes, true);
});

test("survivors at the end date share the win", () => {
  // Ends after day 2.
  const result = evaluateLastStanding(
    challenge({endsAt: ts(DAY1_START + 2 * 24 * HOUR)}),
    [
      player("a", {"2026-10-05": 30, "2026-10-06": 30}),
      player("b", {"2026-10-05": 30, "2026-10-06": 31}),
    ],
    noonOfDay(3)
  );

  assert.equal(result.completes, true);
  assert.deepEqual(result.winnerUids, ["a", "b"]);
  assert.equal(result.update?.lastEvaluatedDay, "2026-10-06");
});

test("days after the end date are never judged", () => {
  const result = evaluateLastStanding(
    challenge({endsAt: ts(DAY1_START + 24 * HOUR)}),
    [player("a", {"2026-10-05": 30}), player("b", {"2026-10-05": 30})],
    noonOfDay(4)
  );

  assert.deepEqual(result.eliminations, []);
  assert.equal(result.update?.lastEvaluatedDay, "2026-10-05");
  assert.deepEqual(result.winnerUids, ["a", "b"]);
});

test("a solo player is never declared winner by outlasting nobody", () => {
  const survived = evaluateLastStanding(
    challenge(),
    [player("a", {"2026-10-05": 30})],
    noonOfDay(2)
  );
  assert.equal(survived.completes, false);
  assert.equal(survived.update?.startingParticipantCount, 1);

  const missed = evaluateLastStanding(
    challenge({lastEvaluatedDay: "2026-10-05", startingParticipantCount: 1}),
    [player("a", {"2026-10-05": 30})],
    noonOfDay(3)
  );
  assert.equal(missed.completes, true);
  assert.deepEqual(missed.winnerUids, []);
  assert.deepEqual(missed.eliminations.map((e) => e.uid), ["a"]);
});

test("someone leaving can hand the last player the win", () => {
  // b left (their participant doc is gone); no new day to judge.
  const result = evaluateLastStanding(
    challenge({lastEvaluatedDay: "2026-10-05", startingParticipantCount: 2}),
    [player("a", {"2026-10-05": 30})],
    noonOfDay(2) + 3 * HOUR
  );

  assert.deepEqual(result.winnerUids, ["a"]);
  assert.equal(result.completes, true);
});

test("a day is only judged for people who'd joined by then", () => {
  const result = evaluateLastStanding(
    challenge({lastEvaluatedDay: "2026-10-05", startingParticipantCount: 3}),
    [
      player("a", {"2026-10-06": 30}),
      player("b", {"2026-10-06": 30}),
      player("late", {}, {joinedDay: "2026-10-07"}),
    ],
    noonOfDay(3)
  );

  assert.deepEqual(result.eliminations, []);
});

test("already-eliminated players stay out of the judging", () => {
  const result = evaluateLastStanding(
    challenge({lastEvaluatedDay: "2026-10-05", startingParticipantCount: 3}),
    [
      player("a", {"2026-10-06": 30}),
      player("b", {"2026-10-06": 30}),
      player("out", {}, {eliminatedOnDay: "2026-10-05"}),
    ],
    noonOfDay(3)
  );

  assert.deepEqual(result.eliminations, []);
  assert.equal(result.completes, false);
});

test("the challenge calendar follows its time zone", () => {
  // Jerusalem day 1 = 2026-10-05 local. 22:30 UTC on Oct 5 is already
  // 01:30 on Oct 6 there, so day 1 has ended and can be judged.
  const result = evaluateLastStanding(
    challenge({
      timeZone: "Asia/Jerusalem",
      startsAt: ts(Date.UTC(2026, 9, 4, 21)), // local midnight Oct 5
    }),
    [player("a", {"2026-10-05": 30}), player("b", {"2026-10-05": 0})],
    Date.UTC(2026, 9, 5, 22, 30)
  );

  assert.deepEqual(result.winnerUids, ["a"]);
});

test("a completed challenge is left alone", () => {
  const result = evaluateLastStanding(
    challenge({status: "completed"}),
    [player("a", {}), player("b", {})],
    noonOfDay(5)
  );

  assert.equal(result.update, null);
});
