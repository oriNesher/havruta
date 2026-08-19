import * as assert from "node:assert/strict";
import {test} from "node:test";
import {detectStreakEvents} from "../rules/streak";
import {EventsContext} from "../types";

/**
 * Builds a valid EventsContext fixture, overridable per test.
 * @param {Partial<EventsContext>} overrides Fields to override on the fixture.
 * @return {EventsContext} A complete fixture context.
 */
function baseContext(overrides: Partial<EventsContext> = {}): EventsContext {
  return {
    competitionId: "comp1",
    competitionTitle: "Reading Challenge",
    actorUid: "alice",
    actorUsername: "Alice",
    actorTargetValue: 100,
    beforeProgress: 10,
    afterProgress: 20,
    participants: [],
    participantUids: ["alice", "bob"],
    openTiedEvents: [],
    previousUpdatedAt: null,
    currentUpdatedAt: null,
    firedCloseRaceCheckpoints: [],
    completionsCount: 0,
    todayDateStr: "2026-03-10",
    isNewActiveDay: true,
    newStreakCount: 3,
    ...overrides,
  };
}

test("creates activityStreak when the new streak hits a milestone", () => {
  const drafts = detectStreakEvents(baseContext({newStreakCount: 3}));

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "activityStreak");
  assert.deepEqual(drafts[0].recipients, ["bob"]);
  assert.equal(
    (drafts[0].payload.metadata as {streak: number}).streak,
    3
  );
});

test("does not create activityStreak on a non-milestone streak count", () => {
  const drafts = detectStreakEvents(baseContext({newStreakCount: 4}));

  assert.equal(drafts.length, 0);
});

test("does not create activityStreak when it is not a new active day", () => {
  const drafts = detectStreakEvents(
    baseContext({isNewActiveDay: false, newStreakCount: 7})
  );

  assert.equal(drafts.length, 0);
});

test("creates activityStreak for each configured milestone", () => {
  for (const milestone of [3, 7, 14, 30, 60, 100]) {
    const drafts = detectStreakEvents(
      baseContext({newStreakCount: milestone})
    );

    assert.equal(drafts.length, 1, `expected a draft for ${milestone}`);
  }
});
