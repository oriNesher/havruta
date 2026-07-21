import * as assert from "node:assert/strict";
import {test} from "node:test";
import {detectRankingEvents} from "../rules/ranking";
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
    afterProgress: 60,
    participants: [
      {uid: "alice", username: "Alice", progress: 60, targetValue: 100},
      {uid: "bob", username: "Bob", progress: 50, targetValue: 100},
    ],
    participantUids: ["alice", "bob"],
    existingOpenProgressEvent: null,
    ...overrides,
  };
}

test("creates an overtook event for a participant just passed", () => {
  const drafts = detectRankingEvents(baseContext());

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "overtook");
  assert.deepEqual(drafts[0].recipients, ["bob"]);
  assert.equal(drafts[0].payload.targetUid, "bob");
});

test("does not create an overtook event for a tie", () => {
  const drafts = detectRankingEvents(
    baseContext({afterProgress: 50})
  );

  assert.equal(drafts.length, 0);
});

test("does not create an overtook event when actor was already ahead", () => {
  const drafts = detectRankingEvents(
    baseContext({beforeProgress: 55, afterProgress: 60})
  );

  assert.equal(drafts.length, 0);
});

test("skips ranking detection when actor target value is invalid", () => {
  const drafts = detectRankingEvents(baseContext({actorTargetValue: 0}));

  assert.equal(drafts.length, 0);
});
