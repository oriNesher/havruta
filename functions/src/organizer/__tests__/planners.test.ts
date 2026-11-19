import * as assert from "node:assert/strict";
import {test} from "node:test";
import {parseChallenge} from "../../challenges/model";
import {StandingParticipant} from "../../challenges/standings";
import {planSettingsChange} from "../settings";
import {planEarlyEnd} from "../endEarly";
import {planCorrection, requireReason} from "../correction";
import {organizersToBackfill, planOrganizerChange} from "../organizers";
import {raceCompletesOnRemoval} from "../removal";
import {planReinstatement} from "../reinstate";
import {announcementPushBody, planAnnouncement} from "../announcement";
import {chunk} from "../../notifications/push";
import {
  evaluateLastStanding,
} from "../../challenges/winConditions/lastStanding";
import {OrganizerError} from "../errors";

/**
 * A stand-in for a Firestore Timestamp.
 * @param {number} millis Epoch milliseconds.
 * @return {FirebaseFirestore.Timestamp} A timestamp-shaped object.
 */
function ts(millis: number): FirebaseFirestore.Timestamp {
  return {toMillis: () => millis} as FirebaseFirestore.Timestamp;
}

/**
 * A participant with sensible defaults.
 * @param {string} uid Their uid.
 * @param {Partial<StandingParticipant>} extra Overrides.
 * @return {StandingParticipant} The participant.
 */
function p(
  uid: string,
  extra: Partial<StandingParticipant> = {}
): StandingParticipant {
  return {
    uid,
    username: uid,
    progress: 0,
    targetValue: null,
    dailyProgress: {},
    eliminatedOnDay: null,
    joinedDay: null,
    updatedAtMillis: null,
    ...extra,
  };
}

const HOUR = 3600e3;
const DAY = 24 * HOUR;
const NOW = Date.UTC(2026, 10, 19, 12); // 2026-11-19 12:00 UTC
const TEXT = {title: "Run club", description: ""};

const race = (extra: Record<string, unknown> = {}) => parseChallenge({
  createdBy: "alice",
  winCondition: "firstToTarget",
  sharedTargetValue: 100,
  participantUids: ["alice", "bob"],
  ...extra,
});

const refused = (fn: () => unknown, message: RegExp) =>
  assert.throws(fn, (e: unknown) =>
    e instanceof OrganizerError && message.test(e.message));

// ── Settings ────────────────────────────────────────────────

test("title and description change any time, even when over", () => {
  const plan = planSettingsChange(race({status: "completed"}), TEXT, [],
    {title: " Run club 2 ", description: "Bring water"}, NOW);
  assert.equal(plan.title, "Run club 2");
  assert.equal(plan.description, "Bring water");
  assert.deepEqual(plan.changes.title,
    {before: "Run club", after: "Run club 2"});
});

test("an unchanged value is no change at all", () => {
  refused(() => planSettingsChange(race(), TEXT, [], {title: "Run club"}, NOW),
    /Nothing changed/);
});

test("rules can't change once the challenge is over", () => {
  refused(() => planSettingsChange(race({status: "completed"}), TEXT, [],
    {targetValue: 200}, NOW), /over/);
  refused(() => planSettingsChange(race({endsAt: ts(NOW - 1)}), TEXT, [],
    {endsAtMillis: NOW + DAY}, NOW), /over/);
});

test("a race target can always be raised", () => {
  const plan = planSettingsChange(race(), TEXT, [p("alice", {progress: 90})],
    {targetValue: 150}, NOW);
  assert.equal(plan.targetValue, 150);
  assert.deepEqual(plan.changes.targetValue, {before: 100, after: 150});
});

test("a race target is lowered only above everyone's progress", () => {
  const people = [p("alice", {progress: 60}), p("bob", {progress: 30})];
  assert.equal(
    planSettingsChange(race(), TEXT, people, {targetValue: 61}, NOW)
      .targetValue,
    61);
  refused(() => planSettingsChange(race(), TEXT, people, {targetValue: 60},
    NOW), /alice already reached it/);
});

test("only a non-legacy race has a target to change", () => {
  refused(() => planSettingsChange(
    parseChallenge({winCondition: "mostProgress"}), TEXT, [],
    {targetValue: 5}, NOW), /Only a Race/);
  refused(() => planSettingsChange(
    parseChallenge({type: "personalGoalChallenge"}), TEXT, [],
    {targetValue: 5}, NOW), /Only a Race/);
  refused(() => planSettingsChange(race(), TEXT, [], {targetValue: 2.5}, NOW),
    /whole number/);
});

test("the daily minimum is Last One Standing only", () => {
  const los = parseChallenge({
    winCondition: "lastStanding", rules: {dailyMinimum: 30},
    startsAt: ts(NOW - 3 * DAY),
  });
  assert.equal(
    planSettingsChange(los, TEXT, [], {dailyMinimum: 20}, NOW).dailyMinimum,
    20);
  refused(() => planSettingsChange(race(), TEXT, [], {dailyMinimum: 20}, NOW),
    /daily minimum/);
});

test("the start moves only before the challenge starts", () => {
  const upcoming = race({startsAt: ts(NOW + DAY)});
  assert.equal(planSettingsChange(upcoming, TEXT, [],
    {startsAtMillis: NOW + 2 * DAY}, NOW).startsAtMillis, NOW + 2 * DAY);
  refused(() => planSettingsChange(upcoming, TEXT, [],
    {startsAtMillis: NOW - HOUR}, NOW), /future/);
  refused(() => planSettingsChange(race({startsAt: ts(NOW - DAY)}), TEXT, [],
    {startsAtMillis: NOW + DAY}, NOW), /already started/);
  // No start at all means it began at creation.
  refused(() => planSettingsChange(race(), TEXT, [],
    {startsAtMillis: NOW + DAY}, NOW), /already started/);
});

test("the end moves to the future, after the start", () => {
  const plan = planSettingsChange(race({endsAt: ts(NOW + DAY)}), TEXT, [],
    {endsAtMillis: NOW + 5 * DAY}, NOW);
  assert.equal(plan.endsAtMillis, NOW + 5 * DAY);
  refused(() => planSettingsChange(race({endsAt: ts(NOW + DAY)}), TEXT, [],
    {endsAtMillis: NOW - HOUR}, NOW), /end the challenge early/);
  refused(() => planSettingsChange(race({startsAt: ts(NOW + 3 * DAY)}), TEXT,
    [], {endsAtMillis: NOW + DAY}, NOW), /after the start/);
});

test("the end can be removed, except from Most Progress", () => {
  assert.equal(planSettingsChange(race({endsAt: ts(NOW + DAY)}), TEXT, [],
    {endsAtMillis: null}, NOW).endsAtMillis, null);
  refused(() => planSettingsChange(parseChallenge({
    winCondition: "mostProgress", endsAt: ts(NOW + DAY),
  }), TEXT, [], {endsAtMillis: null}, NOW), /needs an end date/);
});

// ── Ending early ────────────────────────────────────────────

test("ending a race early: an existing winner stands", () => {
  const plan = planEarlyEnd(race({winnerUids: ["bob"]}),
    [p("alice", {progress: 90}), p("bob", {progress: 100})], NOW);
  assert.deepEqual(plan.winnerUids, ["bob"]);
  assert.deepEqual(plan.placements, []);
  assert.equal(plan.update.status, "completed");
});

test("ending a race early: otherwise the furthest along wins", () => {
  const plan = planEarlyEnd(race(),
    [p("alice", {progress: 40}), p("bob", {progress: 70})], NOW);
  assert.deepEqual(plan.winnerUids, ["bob"]);
  assert.deepEqual(plan.placements, [{uid: "bob", position: 1}]);
});

test("ending Most Progress early: the highest total wins", () => {
  const plan = planEarlyEnd(
    parseChallenge({winCondition: "mostProgress", endsAt: ts(NOW + DAY)}),
    [p("alice", {progress: 12}), p("bob", {progress: 30})], NOW);
  assert.deepEqual(plan.winnerUids, ["bob"]);
});

test("ending Last One Standing early: ended days are judged, " +
  "survivors share the win", () => {
  const los = parseChallenge({
    winCondition: "lastStanding", rules: {dailyMinimum: 10},
    startsAt: ts(Date.UTC(2026, 10, 17)), lastEvaluatedDay: "2026-11-17",
  });
  const plan = planEarlyEnd(los, [
    p("alice", {dailyProgress: {"2026-11-18": 10}}),
    p("bob", {dailyProgress: {"2026-11-18": 12}}),
    p("carol", {dailyProgress: {"2026-11-18": 3}}),
    p("dan", {eliminatedOnDay: "2026-11-17"}),
  ], NOW);
  assert.deepEqual(plan.eliminations.map((e) => e.uid), ["carol"]);
  assert.deepEqual(plan.winnerUids, ["alice", "bob"]);
  assert.equal(plan.update.lastEvaluatedDay, "2026-11-18");
  assert.equal(plan.update.status, "completed");
});

test("today's unfinished day doesn't count against anyone", () => {
  const los = parseChallenge({
    winCondition: "lastStanding", rules: {dailyMinimum: 10},
    startsAt: ts(Date.UTC(2026, 10, 19)),
  });
  const plan = planEarlyEnd(los, [p("alice"), p("bob")], NOW);
  assert.deepEqual(plan.eliminations, []);
  assert.deepEqual(plan.winnerUids, ["alice", "bob"]);
});

test("a Last One Standing that hasn't started ends with no winner", () => {
  const los = parseChallenge({
    winCondition: "lastStanding", rules: {dailyMinimum: 10},
    startsAt: ts(NOW + DAY),
  });
  assert.deepEqual(planEarlyEnd(los, [p("alice"), p("bob")], NOW).winnerUids,
    []);
});

test("a finished challenge can't be ended again", () => {
  refused(() => planEarlyEnd(race({status: "completed"}), [], NOW),
    /already over/);
});

// ── Corrections ─────────────────────────────────────────────

test("a correction lands on today by default", () => {
  const plan = planCorrection(race(),
    p("bob", {progress: 50, dailyProgress: {"2026-11-19": 20}}), 35,
    undefined, NOW);
  assert.deepEqual(plan, {
    from: 50, to: 35, delta: -15, dayKey: "2026-11-19", dayAmount: 5,
  });
});

test("a correction can't take more off a day than it had", () => {
  refused(() => planCorrection(race(),
    p("bob", {progress: 50, dailyProgress: {"2026-11-19": 5}}), 35,
    undefined, NOW), /Only 5 was logged/);
});

test("a correction can add to an earlier day", () => {
  const plan = planCorrection(race(), p("bob", {progress: 50}), 60,
    "2026-11-15", NOW);
  assert.equal(plan.dayKey, "2026-11-15");
  assert.equal(plan.dayAmount, 10);
});

test("judged Last One Standing days and future days are off limits", () => {
  const los = parseChallenge({
    winCondition: "lastStanding", rules: {dailyMinimum: 10},
    startsAt: ts(Date.UTC(2026, 10, 10)), lastEvaluatedDay: "2026-11-18",
  });
  refused(() => planCorrection(los, p("bob"), 10, "2026-11-18", NOW),
    /already been judged/);
  assert.equal(planCorrection(los, p("bob"), 10, "2026-11-19", NOW).dayKey,
    "2026-11-19");
  refused(() => planCorrection(race(), p("bob"), 10, "2026-11-20", NOW),
    /future day/);
  refused(() => planCorrection(los, p("bob"), 10, "2026-11-01", NOW),
    /before the challenge started/);
});

test("corrections refuse the eliminated, no-ops and bad totals", () => {
  refused(() => planCorrection(race(),
    p("bob", {eliminatedOnDay: "2026-11-18"}), 5, undefined, NOW),
  /eliminated/);
  refused(() => planCorrection(race(), p("bob", {progress: 5}), 5,
    undefined, NOW), /already has 5/);
  refused(() => planCorrection(race(), p("bob"), -1, undefined, NOW),
    /whole number/);
  refused(() => planCorrection(race({status: "completed"}), p("bob"), 5,
    undefined, NOW), /final/);
});

test("a correction needs a reason", () => {
  assert.equal(requireReason("  typo in km  "), "typo in km");
  refused(() => requireReason("   "), /reason/);
  refused(() => requireReason("x".repeat(501)), /reason/);
});

// ── Co-organizers ───────────────────────────────────────────

test("co-organizers are added and removed one at a time", () => {
  assert.deepEqual(planOrganizerChange(["alice"], {add: "olga"}),
    ["alice", "olga"]);
  assert.deepEqual(planOrganizerChange(["alice", "olga"], {remove: "alice"}),
    ["olga"]);
  refused(() => planOrganizerChange(["alice"], {add: "olga", remove: "alice"}),
    /exactly one/);
  refused(() => planOrganizerChange(["alice"], {}), /exactly one/);
  refused(() => planOrganizerChange(["alice"], {add: "alice"}),
    /already an organizer/);
  refused(() => planOrganizerChange(["alice"], {remove: "bob"}),
    /aren't an organizer/);
});

test("a challenge always keeps at least one organizer", () => {
  refused(() => planOrganizerChange(["alice"], {remove: "alice"}),
    /at least one organizer/);
});

test("existing challenges migrate their creator to organizer", () => {
  assert.deepEqual(
    organizersToBackfill({createdBy: "alice", participantUids: ["alice"]}),
    ["alice"]);
  assert.equal(organizersToBackfill({createdBy: "alice",
    organizerUids: ["alice", "olga"]}), null);
  assert.equal(organizersToBackfill({createdBy: "alice", organizerUids: []}),
    null);
  assert.equal(organizersToBackfill({}), null);
});

test("there's a cap on organizers", () => {
  const ten = Array.from({length: 10}, (_, i) => `o${i}`);
  refused(() => planOrganizerChange(ten, {add: "x"}), /at most 10/);
});

// ── Reinstating ─────────────────────────────────────────────

const losRunning = () => parseChallenge({
  winCondition: "lastStanding", rules: {dailyMinimum: 10},
  startsAt: ts(Date.UTC(2026, 10, 15)), lastEvaluatedDay: "2026-11-18",
});

test("an eliminated Last One Standing participant can be reinstated", () => {
  assert.deepEqual(
    planReinstatement(losRunning(), p("bob", {eliminatedOnDay: "2026-11-17"})),
    {day: "2026-11-17"});
});

test("nothing to reinstate: still in, not LOS, or over", () => {
  refused(() => planReinstatement(losRunning(), p("bob")), /still in/);
  refused(() => planReinstatement(race(),
    p("bob", {eliminatedOnDay: "2026-11-17"})), /Only Last One Standing/);
  refused(() => planReinstatement(
    parseChallenge({winCondition: "lastStanding", status: "completed"}),
    p("bob", {eliminatedOnDay: "2026-11-17"})), /final/);
});

test("once reinstated, past days stay judged; the next one counts", () => {
  // Eliminated on the 17th, reinstated on the 19th: the 17th and 18th
  // (which they couldn't log on) are never re-judged...
  const reinstated = p("bob", {dailyProgress: {}});
  const alice = p("alice", {dailyProgress: {"2026-11-19": 10}});
  const carol = p("carol", {dailyProgress: {"2026-11-19": 10}});
  const midday19 = Date.UTC(2026, 10, 19, 12);
  assert.deepEqual(
    evaluateLastStanding(losRunning(), [reinstated, alice, carol], midday19)
      .eliminations, []);
  // ...but missing the 19th itself eliminates them as usual.
  const after19 = Date.UTC(2026, 10, 20, 1);
  assert.deepEqual(
    evaluateLastStanding(losRunning(), [reinstated, alice, carol], after19)
      .eliminations.map((e) => e.uid), ["bob"]);
});

// ── Announcements ───────────────────────────────────────────

test("an announcement is trimmed text up to 500 characters", () => {
  assert.equal(planAnnouncement("  Run at 7, bring water ", 0),
    "Run at 7, bring water");
  refused(() => planAnnouncement("   ", 0), /Write something/);
  refused(() => planAnnouncement("x".repeat(501), 0), /at most 500/);
});

test("ten announcements a day, then a pause", () => {
  assert.equal(planAnnouncement("ok", 9), "ok");
  refused(() => planAnnouncement("one more", 10), /limit/);
});

test("the push body names the organizer and fits a lock screen", () => {
  assert.equal(announcementPushBody("Coach", "Run at 7"), "Coach: Run at 7");
  const long = announcementPushBody("Coach", "x".repeat(400));
  assert.ok(long.length <= 160);
  assert.ok(long.endsWith("…"));
});

test("push tokens go out in batches FCM accepts", () => {
  const tokens = Array.from({length: 1201}, (_, i) => `t${i}`);
  assert.deepEqual(chunk(tokens, 500).map((c) => c.length), [500, 500, 201]);
  assert.deepEqual(chunk([], 500), []);
});

// ── Removal ─────────────────────────────────────────────────

test("removing the last runner still racing completes the race", () => {
  const challenge = race({
    participantUids: ["alice", "bob", "carol"],
    finisherUids: ["alice", "bob"], legacyFinisherCount: 0,
  });
  assert.equal(raceCompletesOnRemoval(challenge, "carol"), true);
  assert.equal(raceCompletesOnRemoval(challenge, "bob"), false);
  assert.equal(raceCompletesOnRemoval(
    race({...{participantUids: ["alice", "bob", "carol"]},
      finisherUids: ["alice", "bob"], legacyFinisherCount: 0,
      endsAt: ts(NOW + DAY)}), "carol"), false);
  assert.equal(raceCompletesOnRemoval(
    parseChallenge({winCondition: "mostProgress"}), "carol"), false);
});
