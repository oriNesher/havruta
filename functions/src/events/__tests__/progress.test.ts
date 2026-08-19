import * as assert from "node:assert/strict";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {
  buildProgressEventUpdate,
  detectProgressEvents,
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
    todayDateStr: "2026-01-01",
    isNewActiveDay: false,
    newStreakCount: 0,
    ...overrides,
  };
}

test("produces an upsertProgress draft when no inactivity gap applies", () => {
  const drafts = detectProgressEvents(baseContext(), false);

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "progress");
  assert.deepEqual(drafts[0].target, {kind: "upsertProgress"});
  assert.deepEqual(drafts[0].recipients, ["bob"]);
  assert.equal(drafts[0].payload.beforeProgress, 10);
  assert.equal(drafts[0].payload.afterProgress, 20);
  assert.equal(drafts[0].payload.hasSeparatingEvent, false);
});

test("carries hasSeparatingEvent through to the upsertProgress payload", () => {
  const drafts = detectProgressEvents(baseContext(), true);

  assert.equal(drafts.length, 1);
  assert.deepEqual(drafts[0].target, {kind: "upsertProgress"});
  assert.equal(drafts[0].payload.hasSeparatingEvent, true);
});

test("creates a backInRace event after a long inactivity gap", () => {
  const context = baseContext({
    previousUpdatedAt: Timestamp.fromMillis(0),
    currentUpdatedAt: Timestamp.fromMillis(8 * ONE_DAY_MS),
  });

  const drafts = detectProgressEvents(context, false);

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

  const drafts = detectProgressEvents(context, false);

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "progress");
});

test("does not create backInRace when the gap is under the threshold", () => {
  const context = baseContext({
    previousUpdatedAt: Timestamp.fromMillis(0),
    currentUpdatedAt: Timestamp.fromMillis(3 * ONE_DAY_MS),
  });

  const drafts = detectProgressEvents(context, false);

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "progress");
});

test("buildProgressEventUpdate starts fresh metadata with no existing " +
  "event", () => {
  const result = buildProgressEventUpdate(undefined, 10, 20, false);

  assert.equal(result.status, "open");
  assert.deepEqual(result.metadata, {
    beforeProgress: 10,
    afterProgress: 20,
    progressDelta: 10,
    updatesCount: 1,
  });
});

test("buildProgressEventUpdate merges onto existing metadata", () => {
  const result = buildProgressEventUpdate(
    {beforeProgress: 10, afterProgress: 20, progressDelta: 10, updatesCount: 1},
    20,
    35,
    false
  );

  assert.equal(result.status, "open");
  assert.deepEqual(result.metadata, {
    beforeProgress: 10,
    afterProgress: 35,
    progressDelta: 25,
    updatesCount: 2,
  });
});

test("buildProgressEventUpdate closes when a separator fired, whether " +
  "creating fresh or merging", () => {
  const fresh = buildProgressEventUpdate(undefined, 10, 20, true);
  assert.equal(fresh.status, "closed");

  const merged = buildProgressEventUpdate(
    {beforeProgress: 10, afterProgress: 20, progressDelta: 10, updatesCount: 1},
    20,
    35,
    true
  );
  assert.equal(merged.status, "closed");
});
