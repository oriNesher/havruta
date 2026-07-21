import * as assert from "node:assert/strict";
import {test} from "node:test";
import {detectProgressEvents} from "../rules/progress";
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
    existingOpenProgressEvent: null,
    ...overrides,
  };
}

test("creates a new progress event when none is open", () => {
  const drafts = detectProgressEvents(baseContext());

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "progress");
  assert.deepEqual(drafts[0].target, {kind: "create"});
  assert.deepEqual(drafts[0].recipients, ["bob"]);
  assert.deepEqual(drafts[0].payload.metadata, {
    beforeProgress: 10,
    afterProgress: 20,
    progressDelta: 10,
    updatesCount: 1,
  });
});

test("merges into an existing open progress event", () => {
  const context = baseContext({
    beforeProgress: 20,
    afterProgress: 35,
    existingOpenProgressEvent: {
      id: "existing-event",
      data: {
        metadata: {
          beforeProgress: 10,
          afterProgress: 20,
          progressDelta: 10,
          updatesCount: 1,
        },
      },
    },
  });

  const drafts = detectProgressEvents(context);

  assert.equal(drafts.length, 1);
  assert.deepEqual(drafts[0].target, {
    kind: "update",
    docId: "existing-event",
  });
  assert.deepEqual(drafts[0].payload.metadata, {
    beforeProgress: 10,
    afterProgress: 35,
    progressDelta: 25,
    updatesCount: 2,
  });
});
