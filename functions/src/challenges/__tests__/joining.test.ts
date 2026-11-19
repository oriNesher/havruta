import * as assert from "node:assert/strict";
import {test} from "node:test";
import {
  joinClosedReason,
  personalGoalFields,
  sharedGoalFields,
} from "../joining";
import {isChallengeMember, parseChallenge} from "../model";

/**
 * A stand-in for a Firestore Timestamp.
 * @param {number} millis Epoch milliseconds.
 * @return {FirebaseFirestore.Timestamp} A timestamp-shaped object.
 */
function ts(millis: number): FirebaseFirestore.Timestamp {
  return {toMillis: () => millis} as FirebaseFirestore.Timestamp;
}

const DAY1 = Date.UTC(2026, 9, 5);
const HOUR = 60 * 60 * 1000;

test("an active challenge with no schedule is open", () => {
  assert.equal(joinClosedReason(parseChallenge({}), DAY1), null);
});

test("a completed challenge is closed", () => {
  assert.match(
    joinClosedReason(parseChallenge({status: "completed"}), DAY1) ?? "",
    /no longer active/
  );
});

test("a challenge past its end time is closed", () => {
  const challenge = parseChallenge({endsAt: ts(DAY1)});
  assert.notEqual(joinClosedReason(challenge, DAY1 + 1), null);
  assert.equal(joinClosedReason(challenge, DAY1 - 1), null);
});

test("Last One Standing stays open through day 1, then closes", () => {
  const challenge = parseChallenge({
    winCondition: "lastStanding",
    startsAt: ts(DAY1),
    rules: {dailyMinimum: 30},
  });

  assert.equal(joinClosedReason(challenge, DAY1 - HOUR), null);
  assert.equal(joinClosedReason(challenge, DAY1 + 23 * HOUR), null);
  assert.match(
    joinClosedReason(challenge, DAY1 + 25 * HOUR) ?? "",
    /already started/
  );
});

test("joiners copy the race target, and only a race's", () => {
  assert.deepEqual(
    sharedGoalFields(parseChallenge({
      sharedGoalTitle: "Run",
      sharedTargetValue: 100,
      sharedUnit: "km",
    })),
    {goalTitle: "Run", unit: "km", targetValue: 100}
  );
  assert.deepEqual(
    sharedGoalFields(parseChallenge({
      winCondition: "mostProgress",
      sharedGoalTitle: "Read",
      sharedUnit: "pages",
    })),
    {goalTitle: "Read", unit: "pages"}
  );
});

test("a legacy personal joiner must bring a goal and a target", () => {
  assert.deepEqual(
    personalGoalFields({goalTitle: "Read", targetValue: 20}),
    {goalTitle: "Read", targetValue: 20, unit: ""}
  );
  assert.deepEqual(
    personalGoalFields({goalTitle: "Run", targetValue: 5, unit: "km"}),
    {goalTitle: "Run", targetValue: 5, unit: "km"}
  );
  assert.equal(personalGoalFields({targetValue: 20}), null);
  assert.equal(personalGoalFields({goalTitle: " ", targetValue: 20}), null);
  assert.equal(personalGoalFields({goalTitle: "Read", targetValue: 0}), null);
  assert.equal(personalGoalFields({goalTitle: "Read", targetValue: "9"}),
    null);
});

test("members are participants or organizers", () => {
  const challenge = parseChallenge({
    createdBy: "alice",
    participantUids: ["alice", "bob"],
    organizerUids: ["alice", "olga"],
  });
  assert.equal(isChallengeMember(challenge, "bob"), true);
  assert.equal(isChallengeMember(challenge, "olga"), true);
  assert.equal(isChallengeMember(challenge, "sam"), false);
});

test("a challenge without organizerUids is organized by its creator", () => {
  const challenge = parseChallenge({
    createdBy: "alice",
    participantUids: ["alice", "bob"],
  });
  assert.deepEqual(challenge.organizerUids, ["alice"]);
  assert.deepEqual(parseChallenge({}).organizerUids, []);
});
