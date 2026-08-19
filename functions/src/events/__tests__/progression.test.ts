import * as assert from "node:assert/strict";
import {test} from "node:test";
import {detectProgressionEvents} from "../rules/progression";
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
    todayDateStr: "2026-01-01",
    isNewActiveDay: false,
    newStreakCount: 0,
    ...overrides,
  };
}

test("creates won for the first participant to complete", () => {
  const drafts = detectProgressionEvents(
    baseContext({beforeProgress: 90, afterProgress: 100, completionsCount: 0})
  );

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "won");
  assert.equal(
    (drafts[0].payload.metadata as {position: number}).position,
    1
  );
});

test("creates finishedInPosition for a later completion", () => {
  const drafts = detectProgressionEvents(
    baseContext({beforeProgress: 90, afterProgress: 100, completionsCount: 2})
  );

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "finishedInPosition");
  assert.equal(
    (drafts[0].payload.metadata as {position: number}).position,
    3
  );
});

test("completing overshoots the target and still fires exactly once", () => {
  const drafts = detectProgressionEvents(
    baseContext({beforeProgress: 90, afterProgress: 130, completionsCount: 0})
  );

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "won");
});

test("a direct jump to completion does not also create nearCompletion",
  () => {
    const drafts = detectProgressionEvents(
      baseContext({beforeProgress: 20, afterProgress: 100})
    );

    assert.equal(drafts.length, 1);
    assert.equal(drafts[0].type, "won");
  });

test("creates nearCompletion when entering the final stretch", () => {
  const drafts = detectProgressionEvents(
    baseContext({beforeProgress: 85, afterProgress: 92})
  );

  const nearCompletion = drafts.find((d) => d.type === "nearCompletion");
  assert.ok(nearCompletion);
});

test("does not re-create nearCompletion on a later update past 90", () => {
  const drafts = detectProgressionEvents(
    baseContext({beforeProgress: 92, afterProgress: 95})
  );

  assert.equal(drafts.filter((d) => d.type === "nearCompletion").length, 0);
});

test("creates the highest crossed milestone only", () => {
  const drafts = detectProgressionEvents(
    baseContext({beforeProgress: 20, afterProgress: 80})
  );

  const milestoneDrafts = drafts.filter((d) => d.type === "milestone");
  assert.equal(milestoneDrafts.length, 1);
  assert.equal(
    (milestoneDrafts[0].payload.metadata as {milestone: number}).milestone,
    75
  );
});

test("nearCompletion replaces the 90 milestone but a lower one still fires",
  () => {
    const drafts = detectProgressionEvents(
      baseContext({beforeProgress: 20, afterProgress: 92})
    );

    const milestoneDrafts = drafts.filter((d) => d.type === "milestone");
    assert.equal(milestoneDrafts.length, 1);
    assert.equal(
      (milestoneDrafts[0].payload.metadata as {milestone: number}).milestone,
      75
    );
    assert.equal(drafts.filter((d) => d.type === "nearCompletion").length, 1);
  });

test("does not re-create a milestone already crossed before this update",
  () => {
    const drafts = detectProgressionEvents(
      baseContext({beforeProgress: 76, afterProgress: 80})
    );

    assert.equal(drafts.filter((d) => d.type === "milestone").length, 0);
  });

test("skips progression detection when actor target value is invalid", () => {
  const drafts = detectProgressionEvents(
    baseContext({actorTargetValue: 0})
  );

  assert.equal(drafts.length, 0);
});
