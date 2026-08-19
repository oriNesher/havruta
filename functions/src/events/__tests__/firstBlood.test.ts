import * as assert from "node:assert/strict";
import {test} from "node:test";
import {detectFirstBloodEvents} from "../rules/firstBlood";
import {EventsContext} from "../types";

/**
 * Builds a valid EventsContext fixture, overridable per test. Defaults to
 * the actor's first-ever contribution while every other participant is
 * still at 0 progress.
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
    beforeProgress: 0,
    afterProgress: 5,
    participants: [
      {uid: "alice", username: "Alice", progress: 5, targetValue: 100},
      {uid: "bob", username: "Bob", progress: 0, targetValue: 100},
    ],
    participantUids: ["alice", "bob"],
    openTiedEvents: [],
    previousUpdatedAt: null,
    currentUpdatedAt: null,
    firedCloseRaceCheckpoints: [],
    completionsCount: 0,
    hasFirstBloodEvent: false,
    todayDateStr: "2026-01-01",
    isNewActiveDay: false,
    newStreakCount: 0,
    ...overrides,
  };
}

test("creates firstBlood for the actor's first-ever update when no one" +
  " else has logged progress", () => {
  const drafts = detectFirstBloodEvents(baseContext());

  assert.equal(drafts.length, 1);
  assert.equal(drafts[0].type, "firstBlood");
  assert.deepEqual(drafts[0].recipients, ["bob"]);
});

test("does not create firstBlood when it isn't the actor's first update",
  () => {
    const drafts = detectFirstBloodEvents(
      baseContext({beforeProgress: 5, afterProgress: 10})
    );

    assert.equal(drafts.length, 0);
  });

test("does not create firstBlood when another participant already logged" +
  " progress", () => {
  const drafts = detectFirstBloodEvents(
    baseContext({
      participants: [
        {uid: "alice", username: "Alice", progress: 5, targetValue: 100},
        {uid: "bob", username: "Bob", progress: 3, targetValue: 100},
      ],
    })
  );

  assert.equal(drafts.length, 0);
});

test("does not create firstBlood when the competition already has one",
  () => {
    const drafts = detectFirstBloodEvents(
      baseContext({hasFirstBloodEvent: true})
    );

    assert.equal(drafts.length, 0);
  });
