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
    openTiedEvents: [],
    previousUpdatedAt: null,
    currentUpdatedAt: null,
    firedCloseRaceCheckpoints: [],
    completionsCount: 0,
    todayDateStr: "2026-01-01",
    isNewActiveDay: false,
    newStreakCount: 0,
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

test("creates a tied event instead of overtook when progress becomes equal",
  () => {
    const drafts = detectRankingEvents(baseContext({afterProgress: 50}));

    assert.equal(drafts.length, 1);
    assert.equal(drafts[0].type, "tied");
    assert.deepEqual(drafts[0].recipients, ["bob"]);
    assert.deepEqual(drafts[0].target, {kind: "create"});
  });

test("updates the existing open tied event for this pair instead of " +
  "creating a duplicate", () => {
  const drafts = detectRankingEvents(baseContext({
    afterProgress: 50,
    openTiedEvents: [
      {id: "existingTiedDoc", data: {actorUid: "bob", targetUid: "alice"}},
    ],
  }));

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "tied");
  assert.deepEqual(drafts[0].target, {
    kind: "update",
    docId: "existingTiedDoc",
  });
  // Actor-first: whoever's update caused this tie leads the message, even
  // though the open event was originally created from Bob's side.
  assert.equal(drafts[0].payload.actorUid, "alice");
  assert.equal(drafts[0].payload.targetUid, "bob");
});

test("does not create a tied event when already tied before this update",
  () => {
    const drafts = detectRankingEvents(
      baseContext({beforeProgress: 50, afterProgress: 55})
    );

    assert.equal(drafts.filter((d) => d.type === "tied").length, 0);
  });

test("creates a tied event for whole-percent ties across different targets",
  () => {
    // 99/300 and 33/100 are both 33% but never divide to equal floats.
    const drafts = detectRankingEvents(baseContext({
      actorTargetValue: 300,
      beforeProgress: 90,
      afterProgress: 99,
      participants: [
        {uid: "alice", username: "Alice", progress: 99, targetValue: 300},
        {uid: "bob", username: "Bob", progress: 33, targetValue: 100},
      ],
    }));

    assert.equal(drafts.length, 1);
    assert.equal(drafts[0].type, "tied");
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

test("creates tookTheLead when actor becomes sole leader with 3+ participants",
  () => {
    const context = baseContext({
      beforeProgress: 20,
      afterProgress: 60,
      participants: [
        {uid: "alice", username: "Alice", progress: 60, targetValue: 100},
        {uid: "bob", username: "Bob", progress: 50, targetValue: 100},
        {uid: "carol", username: "Carol", progress: 30, targetValue: 100},
      ],
      participantUids: ["alice", "bob", "carol"],
    });

    const drafts = detectRankingEvents(context);
    const tookTheLead = drafts.find((d) => d.type === "tookTheLead");

    assert.ok(tookTheLead);
    assert.deepEqual(tookTheLead?.recipients, ["bob", "carol"]);
  });

test("does not create tookTheLead with only 2 participants", () => {
  const drafts = detectRankingEvents(baseContext());

  assert.equal(drafts.filter((d) => d.type === "tookTheLead").length, 0);
});

test("does not create tookTheLead when actor was already the sole leader",
  () => {
    const context = baseContext({
      beforeProgress: 55,
      afterProgress: 90,
      participants: [
        {uid: "alice", username: "Alice", progress: 90, targetValue: 100},
        {uid: "bob", username: "Bob", progress: 50, targetValue: 100},
        {uid: "carol", username: "Carol", progress: 30, targetValue: 100},
      ],
      participantUids: ["alice", "bob", "carol"],
    });

    const drafts = detectRankingEvents(context);

    assert.equal(drafts.filter((d) => d.type === "tookTheLead").length, 0);
  });

test("creates tookTheLead when breaking a tie for first place", () => {
  const context = baseContext({
    beforeProgress: 50,
    afterProgress: 60,
    participants: [
      {uid: "alice", username: "Alice", progress: 60, targetValue: 100},
      {uid: "bob", username: "Bob", progress: 50, targetValue: 100},
      {uid: "carol", username: "Carol", progress: 30, targetValue: 100},
    ],
    participantUids: ["alice", "bob", "carol"],
  });

  const drafts = detectRankingEvents(context);
  const tookTheLead = drafts.find((d) => d.type === "tookTheLead");

  assert.ok(tookTheLead);
});
