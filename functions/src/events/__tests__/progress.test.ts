import * as assert from "node:assert/strict";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {
  buildProgressEventMetadata,
  detectProgressEvents,
  isWithinProgressMergeWindow,
  PROGRESS_MERGE_WINDOW_MS,
} from "../rules/progress";
import {EventsContext} from "../types";

const ONE_DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Builds a valid EventsContext fixture, overridable per test. Defaults to a
 * one-day gap since the last update, well under the back-in-race threshold.
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
    previousUpdatedAt: Timestamp.fromMillis(0),
    currentUpdatedAt: Timestamp.fromMillis(ONE_DAY_MS),
    firedCloseRaceCheckpoints: [],
    completionsCount: 0,
    hasFirstBloodEvent: false,
    todayDateStr: "2026-01-01",
    isNewActiveDay: false,
    newStreakCount: 0,
    ...overrides,
  };
}

test("produces an upsertProgress draft when no inactivity gap applies", () => {
  const drafts = detectProgressEvents(baseContext());

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "progress");
  assert.deepEqual(drafts[0].target, {kind: "upsertProgress"});
  assert.deepEqual(drafts[0].recipients, ["bob"]);
  assert.equal(drafts[0].payload.beforeProgress, 10);
  assert.equal(drafts[0].payload.afterProgress, 20);
});

test("creates a backInRace event after a long inactivity gap", () => {
  const context = baseContext({
    previousUpdatedAt: Timestamp.fromMillis(0),
    currentUpdatedAt: Timestamp.fromMillis(8 * ONE_DAY_MS),
  });

  const drafts = detectProgressEvents(context);

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "backInRace");
  assert.deepEqual(drafts[0].target, {kind: "create"});
});

test("does not create backInRace for the actor's first-ever update", () => {
  const context = baseContext({
    beforeProgress: 0,
    previousUpdatedAt: Timestamp.fromMillis(0),
    currentUpdatedAt: Timestamp.fromMillis(30 * ONE_DAY_MS),
  });

  const drafts = detectProgressEvents(context);

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "progress");
});

test("does not create backInRace when the gap is under the threshold", () => {
  const context = baseContext({
    previousUpdatedAt: Timestamp.fromMillis(0),
    currentUpdatedAt: Timestamp.fromMillis(3 * ONE_DAY_MS),
  });

  const drafts = detectProgressEvents(context);

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "progress");
});

test("buildProgressEventMetadata starts fresh with no existing event", () => {
  const metadata = buildProgressEventMetadata(undefined, 10, 20);

  assert.deepEqual(metadata, {
    beforeProgress: 10,
    afterProgress: 20,
    progressDelta: 10,
    updatesCount: 1,
  });
});

test("buildProgressEventMetadata merges onto existing metadata", () => {
  const metadata = buildProgressEventMetadata(
    {beforeProgress: 10, afterProgress: 20, progressDelta: 10, updatesCount: 1},
    20,
    35
  );

  assert.deepEqual(metadata, {
    beforeProgress: 10,
    afterProgress: 35,
    progressDelta: 25,
    updatesCount: 2,
  });
});

test("buildProgressEventMetadata stays correct when a later update's " +
  "invocation is processed before an earlier one's (out-of-order trigger " +
  "delivery)", () => {
  // Real order was 10->20 then 20->35, but the second one's Cloud Function
  // invocation happened to commit first.
  const afterSecondTap = buildProgressEventMetadata(undefined, 20, 35);
  const afterFirstTap = buildProgressEventMetadata(afterSecondTap, 10, 20);

  assert.deepEqual(afterFirstTap, {
    beforeProgress: 10,
    afterProgress: 35,
    progressDelta: 25,
    updatesCount: 2,
  });
});

test("isWithinProgressMergeWindow is false with no existing event", () => {
  const now = Timestamp.fromMillis(1_000_000);
  assert.equal(isWithinProgressMergeWindow(undefined, now), false);
});

test("isWithinProgressMergeWindow merges updates inside the window", () => {
  const lastUpdatedAt = Timestamp.fromMillis(1_000_000);
  const now = Timestamp.fromMillis(1_000_000 + PROGRESS_MERGE_WINDOW_MS);
  assert.equal(isWithinProgressMergeWindow(lastUpdatedAt, now), true);
});

test("isWithinProgressMergeWindow starts fresh once the window lapses", () => {
  const lastUpdatedAt = Timestamp.fromMillis(1_000_000);
  const now = Timestamp.fromMillis(1_000_000 + PROGRESS_MERGE_WINDOW_MS + 1);
  assert.equal(isWithinProgressMergeWindow(lastUpdatedAt, now), false);
});
