import * as assert from "node:assert/strict";
import {test} from "node:test";
import {detectGapEvents} from "../rules/gap";
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
    afterProgress: 40,
    participants: [
      {uid: "alice", username: "Alice", progress: 40, targetValue: 100},
      {uid: "bob", username: "Bob", progress: 42, targetValue: 100},
    ],
    participantUids: ["alice", "bob"],
    existingOpenProgressEvent: null,
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

test("creates closeBehindYou when crossing into close range from behind",
  () => {
    const drafts = detectGapEvents(baseContext());

    const closeBehindYou = drafts.find((d) => d.type === "closeBehindYou");
    assert.ok(closeBehindYou);
    assert.deepEqual(closeBehindYou?.recipients, ["bob"]);
  });

test("does not create closeBehindYou when already within range before", () => {
  const drafts = detectGapEvents(
    baseContext({beforeProgress: 38, afterProgress: 40})
  );

  assert.equal(
    drafts.filter((d) => d.type === "closeBehindYou").length,
    0
  );
});

test("does not create closeBehindYou for a tie or overtake", () => {
  const drafts = detectGapEvents(
    baseContext({beforeProgress: 10, afterProgress: 42})
  );

  assert.equal(
    drafts.filter((d) => d.type === "closeBehindYou").length,
    0
  );
});

test("creates pullingAhead when the leader opens a 3-point gap", () => {
  const context = baseContext({
    beforeProgress: 38,
    afterProgress: 45,
    participants: [
      {uid: "alice", username: "Alice", progress: 45, targetValue: 100},
      {uid: "bob", username: "Bob", progress: 40, targetValue: 100},
    ],
  });

  const drafts = detectGapEvents(context);
  const pullingAhead = drafts.find((d) => d.type === "pullingAhead");

  assert.ok(pullingAhead);
  assert.deepEqual(pullingAhead?.recipients, ["bob"]);
});

test("does not create pullingAhead when the gap was already wide", () => {
  const context = baseContext({
    beforeProgress: 60,
    afterProgress: 70,
    participants: [
      {uid: "alice", username: "Alice", progress: 70, targetValue: 100},
      {uid: "bob", username: "Bob", progress: 40, targetValue: 100},
    ],
  });

  const drafts = detectGapEvents(context);

  assert.equal(drafts.filter((d) => d.type === "pullingAhead").length, 0);
});

test("creates closeRace at 90% when the top two are within 4 points", () => {
  const context = baseContext({
    beforeProgress: 80,
    afterProgress: 92,
    participants: [
      {uid: "alice", username: "Alice", progress: 92, targetValue: 100},
      {uid: "bob", username: "Bob", progress: 89, targetValue: 100},
    ],
  });

  const drafts = detectGapEvents(context);
  const closeRace = drafts.find((d) => d.type === "closeRace");

  assert.ok(closeRace);
  assert.equal(closeRace?.payload.metadata &&
    (closeRace.payload.metadata as {checkpoint: number}).checkpoint, 90);
});

test("does not create closeRace at 90% when the leader is far ahead", () => {
  const context = baseContext({
    beforeProgress: 80,
    afterProgress: 92,
    participants: [
      {uid: "alice", username: "Alice", progress: 92, targetValue: 100},
      {uid: "bob", username: "Bob", progress: 50, targetValue: 100},
    ],
  });

  const drafts = detectGapEvents(context);

  assert.equal(drafts.filter((d) => d.type === "closeRace").length, 0);
});

test("does not re-create closeRace once 90% has already fired", () => {
  const context = baseContext({
    beforeProgress: 80,
    afterProgress: 92,
    participants: [
      {uid: "alice", username: "Alice", progress: 92, targetValue: 100},
      {uid: "bob", username: "Bob", progress: 89, targetValue: 100},
    ],
    firedCloseRaceCheckpoints: [90],
  });

  const drafts = detectGapEvents(context);

  assert.equal(drafts.filter((d) => d.type === "closeRace").length, 0);
});

test("skips gap detection when actor target value is invalid", () => {
  const drafts = detectGapEvents(baseContext({actorTargetValue: 0}));

  assert.equal(drafts.length, 0);
});
