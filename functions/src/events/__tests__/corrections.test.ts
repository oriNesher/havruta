import * as assert from "node:assert/strict";
import {test} from "node:test";
import {isOrganizerCorrection, keepForCorrection} from "../corrections";
import {detectProgressionEvents} from "../rules/progression";
import {parseChallenge} from "../../challenges/model";
import {EventDraft, EventsContext} from "../types";

test("a fresh lastCorrectionId marks an organizer correction", () => {
  assert.equal(isOrganizerCorrection({}, {lastCorrectionId: "e1"}), true);
  assert.equal(
    isOrganizerCorrection({lastCorrectionId: "e1"}, {lastCorrectionId: "e2"}),
    true);
});

test("the participant's own report after a correction isn't one", () => {
  // Their next report leaves the earlier correction's id in place.
  assert.equal(
    isOrganizerCorrection({lastCorrectionId: "e1"}, {lastCorrectionId: "e1"}),
    false);
  assert.equal(isOrganizerCorrection({}, {}), false);
});

const draft = (type: string): EventDraft => ({
  type, recipients: [], target: {kind: "create"}, payload: {},
});

test("a correction keeps only race-finish drafts", () => {
  const kept = keepForCorrection([
    draft("progress"), draft("milestone"), draft("tookTheLead"),
    draft("won"), draft("finishedInPosition"), draft("activityStreak"),
  ]);
  assert.deepEqual(kept.map((d) => d.type), ["won", "finishedInPosition"]);
});

test("a correction across the finish line still finishes the race", () => {
  const context: EventsContext = {
    competitionId: "c1",
    competitionTitle: "Run club",
    challenge: parseChallenge({sharedTargetValue: 100}),
    actorUid: "bob",
    actorUsername: "Bob",
    actorTargetValue: 100,
    beforeProgress: 80,
    afterProgress: 100,
    participants: [
      {uid: "alice", progress: 50, targetValue: 100},
      {uid: "bob", progress: 100, targetValue: 100},
    ],
    participantUids: ["alice", "bob"],
    openTiedEvents: [],
    previousUpdatedAt: null,
    currentUpdatedAt: null,
    firedCloseRaceCheckpoints: [],
    completionsCount: 0,
    hasFirstBloodEvent: true,
    todayDateStr: "2026-11-19",
    isNewActiveDay: false,
    newStreakCount: 0,
  };
  const kept = keepForCorrection(detectProgressionEvents(context));
  assert.equal(kept.length, 1);
  assert.equal(kept[0].type, "won");
  assert.equal(kept[0].payload.actorUid, "bob");
});
