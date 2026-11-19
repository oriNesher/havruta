import * as assert from "node:assert/strict";
import {test} from "node:test";
import {parseChallenge} from "../../challenges/model";
import {StandingParticipant} from "../../challenges/standings";
import {buildDigest, localHour} from "../digest";

/**
 * A participant with sensible defaults.
 * @param {string} uid Who.
 * @param {Partial<StandingParticipant>} extra Overrides.
 * @return {StandingParticipant} The participant.
 */
function p(
  uid: string,
  extra: Partial<StandingParticipant> = {}
): StandingParticipant {
  return {
    uid, username: uid, progress: 0, targetValue: null, dailyProgress: {},
    eliminatedOnDay: null, joinedDay: null, updatedAtMillis: null, ...extra,
  };
}

const TODAY = "2026-11-20";

test("everyone gets the day in a line, plus where they stand", () => {
  const digest = buildDigest({
    title: "Run club",
    challenge: parseChallenge({winCondition: "mostProgress"}),
    participants: [
      p("dana", {progress: 50, dailyProgress: {[TODAY]: 5}}),
      p("sam", {progress: 30, dailyProgress: {[TODAY]: 2}}),
      p("lee", {progress: 10}),
    ],
    todayKey: TODAY,
    previousRanks: {dana: 2, sam: 1},
  });
  assert.equal(digest.title, "Run club today");
  assert.equal(digest.summary, "2 logged today · dana leads");
  assert.equal(digest.bodies.dana,
    "2 logged today · dana leads · you're #1 (▲1)");
  assert.equal(digest.bodies.sam,
    "2 logged today · dana leads · you're #2 (▼1)");
  assert.equal(digest.bodies.lee, "2 logged today · dana leads · you're #3");
  assert.deepEqual(digest.ranks, {dana: 1, sam: 2, lee: 3});
});

test("Last One Standing: the evening nudge says what's still needed", () => {
  const digest = buildDigest({
    title: "Plank",
    challenge: parseChallenge({
      winCondition: "lastStanding", rules: {dailyMinimum: 10},
      sharedUnit: "min",
    }),
    participants: [
      p("dana", {dailyProgress: {[TODAY]: 12}}),
      p("sam", {dailyProgress: {[TODAY]: 4}}),
      p("lee", {eliminatedOnDay: "2026-11-18"}),
    ],
    todayKey: TODAY,
    previousRanks: {},
  });
  assert.equal(digest.summary, "2 still in · 2 logged today");
  assert.equal(digest.bodies.dana,
    "2 still in · 2 logged today · you're safe today");
  assert.equal(digest.bodies.sam,
    "2 still in · 2 logged today · you still need 6 min today");
  assert.equal(digest.bodies.lee, "2 still in · 2 logged today");
});

test("nobody leads a day where nobody has logged anything", () => {
  const digest = buildDigest({
    title: "Club",
    challenge: parseChallenge({winCondition: "mostProgress"}),
    participants: [p("a"), p("b")],
    todayKey: TODAY,
    previousRanks: {},
  });
  assert.equal(digest.summary, "0 logged today");
});

test("the digest hour is read in the challenge's own time zone", () => {
  const at1800utc = Date.UTC(2026, 10, 20, 18);
  assert.equal(localHour(at1800utc, "Asia/Jerusalem"), 20);
  assert.equal(localHour(at1800utc, null), 18);
  assert.equal(localHour(at1800utc, "Not/AZone"), 18);
});
