import * as assert from "node:assert/strict";
import {test} from "node:test";
import {parseChallenge} from "../model";

/**
 * A stand-in for a Firestore Timestamp: parseChallenge only checks for
 * toMillis, so tests don't need firebase-admin initialized.
 * @param {number} millis Epoch milliseconds.
 * @return {FirebaseFirestore.Timestamp} A timestamp-shaped object.
 */
function fakeTimestamp(millis: number): FirebaseFirestore.Timestamp {
  return {toMillis: () => millis} as FirebaseFirestore.Timestamp;
}

test("a legacy shared goal challenge parses as a race", () => {
  const challenge = parseChallenge({
    type: "sharedGoalChallenge",
    sharedGoalTitle: "Run",
    sharedTargetValue: 100,
    sharedUnit: "km",
    status: "active",
    winnerUid: null,
  });

  assert.equal(challenge.winCondition, "firstToTarget");
  assert.equal(challenge.isLegacyPersonal, false);
  assert.equal(challenge.goalTitle, "Run");
  assert.equal(challenge.targetValue, 100);
  assert.equal(challenge.unit, "km");
  assert.deepEqual(challenge.winnerUids, []);
});

test("a legacy personal goal challenge is a per-participant race", () => {
  const challenge = parseChallenge({type: "personalGoalChallenge"});

  assert.equal(challenge.winCondition, "firstToTarget");
  assert.equal(challenge.isLegacyPersonal, true);
  assert.equal(challenge.targetValue, null);
});

test("a document with no type at all is a race", () => {
  const challenge = parseChallenge({});

  assert.equal(challenge.winCondition, "firstToTarget");
  assert.equal(challenge.status, "active");
  assert.equal(challenge.timeZone, null);
  assert.equal(challenge.rules.dailyMinimum, null);
  assert.equal(challenge.rules.lives, 0);
});

test("an unknown winCondition falls back to a race", () => {
  const challenge = parseChallenge({winCondition: "bogus"});

  assert.equal(challenge.winCondition, "firstToTarget");
  assert.equal(challenge.isLegacyPersonal, false);
});

test("lastStanding reads its rules, calendar and cursor", () => {
  const challenge = parseChallenge({
    type: "sharedGoalChallenge",
    winCondition: "lastStanding",
    sharedTargetValue: 999,
    rules: {dailyMinimum: 30},
    timeZone: "Asia/Jerusalem",
    startsAt: fakeTimestamp(1000),
    lastEvaluatedDay: "2026-10-05",
  });

  assert.equal(challenge.winCondition, "lastStanding");
  assert.equal(challenge.rules.dailyMinimum, 30);
  assert.equal(challenge.timeZone, "Asia/Jerusalem");
  assert.equal(challenge.startsAt?.toMillis(), 1000);
  assert.equal(challenge.lastEvaluatedDay, "2026-10-05");
  // Only a race has a finish line, even if a stray value is present.
  assert.equal(challenge.targetValue, null);
});

test("mostProgress reads endsAt and has no finish line", () => {
  const challenge = parseChallenge({
    winCondition: "mostProgress",
    endsAt: fakeTimestamp(5000),
  });

  assert.equal(challenge.winCondition, "mostProgress");
  assert.equal(challenge.endsAt?.toMillis(), 5000);
  assert.equal(challenge.targetValue, null);
});

test("winnerUids wins over the legacy winnerUid", () => {
  assert.deepEqual(
    parseChallenge({winnerUids: ["a", "b"], winnerUid: "a"}).winnerUids,
    ["a", "b"]
  );
  assert.deepEqual(parseChallenge({winnerUid: "a"}).winnerUids, ["a"]);
});

test("malformed values are ignored rather than trusted", () => {
  const challenge = parseChallenge({
    rules: {dailyMinimum: -5, lives: "2"},
    endsAt: "2026-11-01",
    finisherUids: ["a", 3, null],
  });

  assert.equal(challenge.rules.dailyMinimum, null);
  assert.equal(challenge.rules.lives, 0);
  assert.equal(challenge.endsAt, null);
  assert.deepEqual(challenge.finisherUids, ["a"]);
});
