import * as assert from "node:assert/strict";
import {test} from "node:test";
import {isCelebrationType} from "../celebrationTypes";
import {
  detectEliminationEvents,
  detectPlacementEvents,
} from "../rules/outcome";

const PARTICIPANTS = [
  {uid: "alice", username: "Alice"},
  {uid: "bob", username: "Bob"},
  {uid: "carol", username: "Carol"},
];

test("an elimination is announced to everyone else", () => {
  const drafts = detectEliminationEvents("Study daily", PARTICIPANTS, [
    {uid: "bob", day: "2026-10-06", dayNumber: 2},
  ]);

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "eliminated");
  assert.deepEqual(drafts[0].recipients, ["alice", "carol"]);
  assert.equal(drafts[0].payload.actorUid, "bob");
  assert.equal(drafts[0].payload.actorUsername, "Bob");
  assert.deepEqual(drafts[0].payload.metadata, {
    day: "2026-10-06",
    dayNumber: 2,
  });
  // News for the others, not a celebration for the person who's out.
  assert.equal(isCelebrationType(drafts[0].type), false);
});

test("placements become won / finishedInPosition events", () => {
  const drafts = detectPlacementEvents("Most km", PARTICIPANTS, [
    {uid: "carol", position: 1},
    {uid: "alice", position: 2},
  ]);

  assert.deepEqual(drafts.map((d) => d.type), ["won", "finishedInPosition"]);
  assert.deepEqual(drafts[0].recipients, ["alice", "bob"]);
  assert.deepEqual(drafts[0].payload.metadata, {
    position: 1,
    decidedAtEnd: true,
  });
  assert.equal(
    (drafts[1].payload.metadata as {position: number}).position,
    2
  );
  // The winner gets the full-screen celebration.
  assert.equal(isCelebrationType("won"), true);
});

test("a shared win is marked as shared", () => {
  const drafts = detectPlacementEvents("Study daily", PARTICIPANTS, [
    {uid: "alice", position: 1},
    {uid: "bob", position: 1},
  ]);

  assert.deepEqual(drafts.map((d) => d.type), ["won", "won"]);
  for (const draft of drafts) {
    assert.equal(
      (draft.payload.metadata as {sharedWin?: boolean}).sharedWin,
      true
    );
  }
});

test("no placements, no events", () => {
  assert.deepEqual(detectPlacementEvents("x", PARTICIPANTS, []), []);
  assert.deepEqual(detectEliminationEvents("x", PARTICIPANTS, []), []);
});
