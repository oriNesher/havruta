import * as assert from "node:assert/strict";
import {test} from "node:test";
import {
  isLargeChallenge,
  LARGE_CHALLENGE_THRESHOLD,
  parseChallenge,
} from "../../challenges/model";
import {audienceFor, buildAudience} from "../audience";
import {EventDraft, EventsContext} from "../types";
import {detectProgressEvents} from "../rules/progress";
import {detectFirstBloodEvents} from "../rules/firstBlood";
import {detectStreakEvents} from "../rules/streak";
import {detectRankingEvents} from "../rules/ranking";
import {detectProgressionEvents} from "../rules/progression";
import {
  detectEliminationEvents,
  detectPlacementEvents,
} from "../rules/outcome";
import {audienceUidsOf} from "../persist";

// 20 participants, p0 leading: p0 has 200, p1 190 … p19 10.
const UIDS = Array.from({length: 20}, (_, i) => `p${i}`);
const progressOf = (uid: string) => (20 - UIDS.indexOf(uid)) * 10;
// p19 follows p10; p0 and p10 are teammates.
const FOLLOWING = {p19: ["p10"]};
const TEAMS: Record<string, string> = {p0: "red", p10: "red"};

const sorted = (uids: string[]) => [...uids].sort();
const others = (actor: string) => sorted(UIDS.filter((u) => u !== actor));

/**
 * A participant doc for the standard field.
 * @param {string} uid Who.
 * @param {number} progress Their progress.
 * @param {number} [targetValue] Race target.
 * @return {object} The doc data.
 */
function doc(uid: string, progress: number, targetValue?: number) {
  return {
    uid,
    username: uid,
    progress,
    ...(targetValue ? {targetValue} : {}),
    ...(TEAMS[uid] ? {teamId: TEAMS[uid]} : {}),
  };
}

/**
 * An events context for `actor` reporting before → after.
 * @param {object} options What to build.
 * @param {string} options.actor The reporter.
 * @param {number} options.before Their progress before.
 * @param {number} options.after Their progress after.
 * @param {Record<string, unknown>} [options.challenge] Challenge doc data.
 * @param {number} [options.size] How many participants (first N of UIDS).
 * @param {function(string): number} [options.progress] Others' progress.
 * @param {Partial<EventsContext>} [options.extra] Context overrides.
 * @return {EventsContext} The context.
 */
function context(options: {
  actor: string;
  before: number;
  after: number;
  challenge?: Record<string, unknown>;
  size?: number;
  progress?: (uid: string) => number;
  extra?: Partial<EventsContext>;
}): EventsContext {
  const uids = UIDS.slice(0, options.size ?? UIDS.length);
  const target = options.challenge?.sharedTargetValue as number | undefined;
  const docs = uids.map((uid) => doc(
    uid,
    uid === options.actor ? options.after :
      (options.progress ?? progressOf)(uid),
    target
  ));
  const challenge = parseChallenge({
    winCondition: "mostProgress",
    participantUids: uids,
    ...options.challenge,
  });
  return {
    competitionId: "c1",
    competitionTitle: "Club",
    challenge,
    actorUid: options.actor,
    actorUsername: options.actor,
    actorTargetValue: target ?? 0,
    beforeProgress: options.before,
    afterProgress: options.after,
    participants: docs,
    participantUids: uids,
    openTiedEvents: [],
    previousUpdatedAt: null,
    currentUpdatedAt: null,
    firedCloseRaceCheckpoints: [],
    completionsCount: 0,
    hasFirstBloodEvent: true,
    todayDateStr: "2026-11-20",
    isNewActiveDay: false,
    newStreakCount: 0,
    audience: buildAudience(challenge, docs, FOLLOWING),
    ...options.extra,
  };
}

const ofType = (drafts: EventDraft[], type: string) =>
  drafts.filter((d) => d.type === type);

// ── When a challenge is large ───────────────────────────────

test("above 15 participants a challenge is large, unless overridden", () => {
  const field = (n: number, social?: Record<string, unknown>) =>
    parseChallenge({participantUids: UIDS.slice(0, n), social});
  assert.equal(LARGE_CHALLENGE_THRESHOLD, 15);
  assert.equal(isLargeChallenge(field(15)), false);
  assert.equal(isLargeChallenge(field(16)), true);
  assert.equal(isLargeChallenge(field(16, {scale: "small"})), false);
  assert.equal(isLargeChallenge(field(4, {scale: "large"})), true);
  assert.equal(isLargeChallenge(field(16, {scale: "bogus"})), true);
});

test("a small challenge has no audience: everyone hears everything", () => {
  const small = parseChallenge({participantUids: UIDS.slice(0, 5)});
  assert.equal(buildAudience(small, [], {}), null);
  assert.deepEqual(
    sorted(audienceFor(null, UIDS.slice(0, 5), "p2", "nearby")),
    ["p0", "p1", "p3", "p4"]);
});

// ── Who hears what ──────────────────────────────────────────

test("nearby: ±3 places, followers and teammates — not the actor", () => {
  const ctx = context({actor: "p10", before: 100, after: 100});
  assert.deepEqual(
    sorted(audienceFor(ctx.audience, UIDS, "p10", "nearby")),
    sorted(["p7", "p8", "p9", "p11", "p12", "p13", "p19", "p0"]));
});

test("social: followers and teammates only", () => {
  const ctx = context({actor: "p10", before: 100, after: 100});
  assert.deepEqual(sorted(audienceFor(ctx.audience, UIDS, "p10", "social")),
    ["p0", "p19"]);
  assert.deepEqual(audienceFor(ctx.audience, UIDS, "p5", "social"), []);
});

test("everyone means everyone else", () => {
  const ctx = context({actor: "p10", before: 100, after: 100});
  assert.deepEqual(sorted(audienceFor(ctx.audience, UIDS, "p10", "everyone")),
    others("p10"));
});

test("the leader's neighborhood stops at the top of the board", () => {
  const ctx = context({actor: "p0", before: 200, after: 200});
  assert.deepEqual(sorted(audienceFor(ctx.audience, UIDS, "p0", "nearby")),
    sorted(["p1", "p2", "p3", "p10"]));
});

// ── Each rule's reach in a large challenge ──────────────────

test("a progress report reaches the neighborhood", () => {
  const drafts = detectProgressEvents(
    context({actor: "p10", before: 100, after: 105}));
  const [progress] = ofType(drafts, "progress");
  assert.deepEqual(sorted(progress.recipients),
    sorted(["p7", "p8", "p9", "p11", "p12", "p13", "p19", "p0"]));
});

test("…but still everyone in a small challenge", () => {
  const drafts = detectProgressEvents(context({
    actor: "p2", before: 180, after: 185, size: 6,
  }));
  assert.deepEqual(sorted(ofType(drafts, "progress")[0].recipients),
    ["p0", "p1", "p3", "p4", "p5"]);
});

test("a streak reaches the neighborhood", () => {
  const [streak] = detectStreakEvents(context({
    actor: "p10", before: 100, after: 105,
    extra: {isNewActiveDay: true, newStreakCount: 3},
  }));
  assert.equal(streak.type, "activityStreak");
  assert.equal(streak.recipients.length, 8);
});

test("first blood is headline news", () => {
  const [firstBlood] = detectFirstBloodEvents(context({
    actor: "p10", before: 0, after: 5, progress: () => 0,
    extra: {hasFirstBloodEvent: false},
  }));
  assert.equal(firstBlood.type, "firstBlood");
  assert.deepEqual(sorted(firstBlood.recipients), others("p10"));
});

test("taking the lead is headline news", () => {
  const drafts = detectRankingEvents(
    context({actor: "p1", before: 190, after: 205}));
  const [lead] = ofType(drafts, "tookTheLead");
  assert.deepEqual(sorted(lead.recipients), others("p1"));
});

test("a race win and the podium go to everyone; later finishes nearby",
  () => {
    const race = {winCondition: "firstToTarget", sharedTargetValue: 250};
    const won = detectProgressionEvents(context({
      actor: "p10", before: 240, after: 250, challenge: race,
    }));
    assert.equal(won[0].type, "won");
    assert.deepEqual(sorted(won[0].recipients), others("p10"));

    const sixth = detectProgressionEvents(context({
      actor: "p10", before: 240, after: 250, challenge: race,
      extra: {completionsCount: 5},
    }));
    assert.equal(sixth[0].type, "finishedInPosition");
    // At 250 they now top the board: the places below, their follower and
    // teammate — not everyone.
    assert.deepEqual(sorted(sixth[0].recipients),
      ["p0", "p1", "p19", "p2"]);
  });

test("a milestone reaches the neighborhood", () => {
  const drafts = detectProgressionEvents(context({
    actor: "p10", before: 120, after: 130,
    challenge: {winCondition: "firstToTarget", sharedTargetValue: 250},
  }));
  const [milestone] = ofType(drafts, "milestone");
  assert.equal(milestone.recipients.length, 8);
});

// ── One celebration for a big jump ──────────────────────────

test("passing many people: each hears it, the actor celebrates once", () => {
  // p15 (60) jumps to 155: passes p5 (150) … p14 (60) — ten people.
  const drafts = detectRankingEvents(
    context({actor: "p15", before: 60, after: 155}));
  const overtakes = ofType(drafts, "overtook");
  assert.equal(overtakes.length, 10);
  for (const draft of overtakes) assert.equal(draft.recipients.length, 1);

  const lead = overtakes.filter((d) => d.payload.actorCelebrated !== true);
  assert.equal(lead.length, 1);
  assert.equal(lead[0].payload.targetUid, "p5");
  assert.equal(
    (lead[0].payload.metadata as Record<string, unknown>).alsoOvertookCount,
    9);
});

test("a few passes, or a small challenge, aren't collapsed", () => {
  const few = ofType(detectRankingEvents(
    context({actor: "p15", before: 60, after: 85})), "overtook");
  assert.equal(few.length, 3);
  assert.ok(few.every((d) => d.payload.actorCelebrated === undefined));

  const small = ofType(detectRankingEvents(context({
    actor: "p9", before: 110, after: 205, size: 10,
  })), "overtook");
  assert.equal(small.length, 9);
  assert.ok(small.every((d) => d.payload.actorCelebrated === undefined));
});

// ── Outcomes ────────────────────────────────────────────────

test("eliminations reach the neighborhood; the podium reaches everyone",
  () => {
    const ctx = context({actor: "p10", before: 100, after: 100});
    const people = UIDS.map((uid) => ({uid, username: uid}));
    const [eliminated] = detectEliminationEvents("Club", people,
      [{uid: "p10", day: "2026-11-19", dayNumber: 4}], ctx.audience);
    assert.equal(eliminated.recipients.length, 8);

    const placements = detectPlacementEvents("Club", people, [
      {uid: "p0", position: 1},
      {uid: "p2", position: 3},
      {uid: "p10", position: 11},
    ], ctx.audience);
    assert.deepEqual(sorted(placements[0].recipients), others("p0"));
    assert.deepEqual(sorted(placements[1].recipients), others("p2"));
    assert.deepEqual(sorted(placements[2].recipients), ["p0", "p19"]);
  });

test("outcomes without an audience go to everyone, as before", () => {
  const people = UIDS.slice(0, 4).map((uid) => ({uid, username: uid}));
  const [eliminated] = detectEliminationEvents("Club", people,
    [{uid: "p1", day: "2026-11-19", dayNumber: 4}]);
  assert.deepEqual(sorted(eliminated.recipients), ["p0", "p2", "p3"]);
});

// ── The feed's permanent audience ───────────────────────────

test("an event's audience is its recipients plus its actor", () => {
  const draft: EventDraft = {
    type: "progress",
    recipients: ["p1", "p2", "p1"],
    target: {kind: "create"},
    payload: {actorUid: "p0"},
  };
  assert.deepEqual(sorted(audienceUidsOf(draft)), ["p0", "p1", "p2"]);
  assert.deepEqual(
    audienceUidsOf({...draft, payload: {}}).sort(), ["p1", "p2"]);
});
