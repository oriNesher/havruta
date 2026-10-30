import * as assert from "node:assert/strict";
import {test} from "node:test";
import {
  AggressorTransfer,
  detectAggressorTakeoverEvents,
} from "../rules/aggressorTakeover";

/**
 * A transfer fixture: Bob takes the badge from Alice with his own progress
 * report, in a three-person challenge.
 * @param {Partial<AggressorTransfer>} overrides Fields to override.
 * @return {AggressorTransfer} A complete fixture transfer.
 */
function transfer(
  overrides: Partial<AggressorTransfer> = {}
): AggressorTransfer {
  return {
    competitionTitle: "Reading Challenge",
    participants: [
      {uid: "alice", username: "Alice"},
      {uid: "bob", username: "Bob"},
      {uid: "carol", username: "Carol"},
    ],
    previousHolderUid: "alice",
    previousHolderUsername: "Alice",
    newHolderUid: "bob",
    cause: "progress",
    reporterUid: "bob",
    scores: [
      {uid: "alice", windowTotal: 10, eligibleDays: 3, updatedAtMillis: 1},
      {uid: "bob", windowTotal: 12, eligibleDays: 3, updatedAtMillis: 2},
      {uid: "carol", windowTotal: 0, eligibleDays: 3, updatedAtMillis: null},
    ],
    windowDays: ["2026-10-10", "2026-10-09", "2026-10-08"],
    ...overrides,
  };
}

test("a transfer creates one takeover naming both holders", () => {
  const drafts = detectAggressorTakeoverEvents(transfer());

  assert.equal(drafts.length, 1);
  const [draft] = drafts;
  assert.equal(draft.type, "aggressorTakeover");
  assert.deepEqual(draft.target, {kind: "create"});
  assert.equal(draft.payload.actorUid, "bob");
  assert.equal(draft.payload.actorUsername, "Bob");
  assert.equal(draft.payload.targetUid, "alice");
  assert.equal(draft.payload.targetUsername, "Alice");
  assert.deepEqual(draft.recipients, ["alice", "carol"]);
  assert.deepEqual(draft.payload.metadata, {
    cause: "progress",
    windowDays: ["2026-10-10", "2026-10-09", "2026-10-08"],
    actorWindowTotal: 12,
    targetWindowTotal: 10,
  });
});

test("celebrated when the new holder won it with their own report", () => {
  const [draft] = detectAggressorTakeoverEvents(transfer());
  assert.equal(draft.payload.actorCelebrated, false);
});

test("no takeover when the holder keeps the badge", () => {
  assert.deepEqual(
    detectAggressorTakeoverEvents(transfer({newHolderUid: "alice"})),
    []
  );
});

test("no takeover when the badge goes vacant", () => {
  assert.deepEqual(
    detectAggressorTakeoverEvents(transfer({newHolderUid: null})),
    []
  );
});

test("a first claim is a takeover with no previous holder", () => {
  const [draft] = detectAggressorTakeoverEvents(transfer({
    previousHolderUid: null,
    previousHolderUsername: null,
  }));
  assert.equal(draft.payload.targetUid, null);
  assert.equal(draft.payload.targetUsername, null);
  assert.equal(
    (draft.payload.metadata as Record<string, unknown>).targetWindowTotal,
    null
  );
  assert.deepEqual(draft.recipients, ["alice", "carol"]);
});

test("no takeover when the badge passes on because its holder left", () => {
  assert.deepEqual(
    detectAggressorTakeoverEvents(transfer({
      cause: "holderLeft",
      reporterUid: null,
      participants: [
        {uid: "bob", username: "Bob"},
        {uid: "carol", username: "Carol"},
      ],
    })),
    []
  );
});

test("a rival taking progress back is news, not a celebration", () => {
  const [draft] = detectAggressorTakeoverEvents(transfer({
    cause: "progressRemoved",
    reporterUid: "alice",
  }));
  assert.equal(draft.payload.actorUid, "bob");
  assert.equal(draft.payload.actorCelebrated, true);
});

test("the window moving at midnight is news, not a celebration", () => {
  const [draft] = detectAggressorTakeoverEvents(transfer({
    cause: "dayRollover",
    reporterUid: null,
  }));
  assert.equal(draft.payload.actorCelebrated, true);
});

test("another player's report handing over the badge isn't celebrated", () => {
  // Carol's report can't make Bob the holder by itself, but if the
  // evaluation it prompted moves the badge to Bob, it's not Bob's moment.
  const [draft] = detectAggressorTakeoverEvents(transfer({
    reporterUid: "carol",
  }));
  assert.equal(draft.payload.actorCelebrated, true);
});

test("a previous holder no longer listed keeps their stored name", () => {
  const [draft] = detectAggressorTakeoverEvents(transfer({
    participants: [
      {uid: "bob", username: "Bob"},
      {uid: "carol", username: "Carol"},
    ],
  }));
  assert.equal(draft.payload.targetUsername, "Alice");
  assert.deepEqual(draft.recipients, ["carol"]);
});
