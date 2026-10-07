import * as assert from "node:assert/strict";
import {test} from "node:test";
import {parseChallenge} from "../model";
import {StandingParticipant} from "../standings";
import {decideDeadlineResult} from "../winConditions/deadline";

/**
 * A participant fixture.
 * @param {string} uid Their uid.
 * @param {number} progress Their total.
 * @param {number} updatedAtMillis When they last logged.
 * @param {Partial<StandingParticipant>} overrides Fields to override.
 * @return {StandingParticipant} The participant.
 */
function player(
  uid: string,
  progress: number,
  updatedAtMillis: number,
  overrides: Partial<StandingParticipant> = {}
): StandingParticipant {
  return {
    uid,
    username: uid,
    progress,
    targetValue: null,
    dailyProgress: {},
    eliminatedOnDay: null,
    joinedDay: null,
    updatedAtMillis,
    ...overrides,
  };
}

const mostProgress = parseChallenge({winCondition: "mostProgress"});

test("most progress wins and everyone who logged is placed", () => {
  const result = decideDeadlineResult(mostProgress, [
    player("a", 40, 1),
    player("b", 90, 2),
    player("c", 0, 3),
    player("d", 60, 4),
  ]);

  assert.deepEqual(result.winnerUids, ["b"]);
  assert.deepEqual(result.placements, [
    {uid: "b", position: 1},
    {uid: "d", position: 2},
    {uid: "a", position: 3},
  ]);
});

test("an equal total goes to whoever got there first", () => {
  const result = decideDeadlineResult(mostProgress, [
    player("late", 50, 200),
    player("early", 50, 100),
  ]);

  assert.deepEqual(result.winnerUids, ["early"]);
  assert.equal(result.placements[1].position, 2);
});

test("an exact tie, to the millisecond, shares the win", () => {
  const result = decideDeadlineResult(mostProgress, [
    player("a", 50, 100),
    player("b", 50, 100),
    player("c", 10, 50),
  ]);

  assert.deepEqual(result.winnerUids, ["a", "b"]);
  assert.deepEqual(result.placements.map((p) => p.position), [1, 1, 3]);
});

test("nobody logging anything means no winner", () => {
  const result = decideDeadlineResult(mostProgress, [
    player("a", 0, 1),
    player("b", 0, 2),
  ]);

  assert.deepEqual(result.winnerUids, []);
  assert.deepEqual(result.placements, []);
});

test("a race's existing winner stands at the deadline", () => {
  const race = parseChallenge({
    sharedTargetValue: 100,
    winnerUids: ["a"],
  });

  const result = decideDeadlineResult(race, [
    player("a", 100, 1),
    player("b", 99, 2),
  ]);

  assert.deepEqual(result.winnerUids, ["a"]);
  assert.deepEqual(result.placements, []);
});

test("a race nobody finished goes to whoever got closest", () => {
  const race = parseChallenge({sharedTargetValue: 100});

  const result = decideDeadlineResult(race, [
    player("a", 40, 1, {targetValue: 100}),
    player("b", 70, 2, {targetValue: 100}),
  ]);

  assert.deepEqual(result.winnerUids, ["b"]);
  assert.deepEqual(result.placements, [{uid: "b", position: 1}]);
});

test("a legacy personal race compares each player's own target", () => {
  const race = parseChallenge({type: "personalGoalChallenge"});

  const result = decideDeadlineResult(race, [
    player("big", 50, 1, {targetValue: 1000}),
    player("small", 8, 2, {targetValue: 10}),
  ]);

  assert.deepEqual(result.winnerUids, ["small"]);
});

test("a race nobody started has no winner", () => {
  const race = parseChallenge({sharedTargetValue: 100});

  const result = decideDeadlineResult(race, [player("a", 0, 1)]);

  assert.deepEqual(result.winnerUids, []);
});
