// Runs the organizer callables (and the invite callables they interact
// with) for real against the Firestore emulator, so their transactions —
// not just the pure planners — are exercised. Part of `npm run test:rules`
// (emulator required). Triggers don't run here; this checks what each
// callable writes.
import * as assert from "node:assert/strict";
import {after, before, beforeEach, describe, test} from "node:test";
import * as admin from "firebase-admin";
import functionsTest = require("firebase-functions-test");

const PROJECT = "demo-havruta-callables";
process.env.GCLOUD_PROJECT = PROJECT;
const fft = functionsTest({projectId: PROJECT});
admin.initializeApp({projectId: PROJECT});

/* eslint-disable @typescript-eslint/no-var-requires */
// Required after initializeApp: the modules read admin.firestore() lazily,
// but keep the order obvious.
const {correctProgress} = require("../../organizer/correctProgress");
const {updateChallengeSettings} =
  require("../../organizer/updateChallengeSettings");
const {removeParticipant} = require("../../organizer/removeParticipant");
const {endChallengeEarly} = require("../../organizer/endChallengeEarly");
const {setOrganizers} = require("../../organizer/setOrganizers");
const {reinstateParticipant} =
  require("../../organizer/reinstateParticipant");
const {acceptInvite} = require("../../invites/acceptInvite");
const {sendAnnouncement} = require("../../organizer/sendAnnouncement");
/* eslint-enable @typescript-eslint/no-var-requires */

const db = admin.firestore();
const race = db.collection("competitions").doc("race");
const DAY = 864e5;

type Callable = Parameters<typeof fft.wrap>[0];

/**
 * Calls a callable as a signed-in user.
 * @param {Callable} fn The callable.
 * @param {string} uid The caller.
 * @param {object} data Its payload.
 * @return {Promise<unknown>} Its result.
 */
function call(fn: Callable, uid: string, data: Record<string, unknown>) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const wrapped = fft.wrap(fn) as any;
  return wrapped({data: {competitionId: "race", ...data}, auth: {uid}});
}

/**
 * Asserts a call is refused with the given HttpsError code.
 * @param {Promise<unknown>} promise The call.
 * @param {string} code The expected code.
 * @param {RegExp} [message] Optional message pattern.
 */
async function refused(
  promise: Promise<unknown>,
  code: string,
  message?: RegExp
): Promise<void> {
  await assert.rejects(promise, (e: {code?: string; message?: string}) =>
    e.code === code && (!message || message.test(e.message ?? "")));
}

const today = () => new Date().toISOString().slice(0, 10);

before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST,
    "Run through `npm run test:rules` so the emulator is up.");
});

after(() => fft.cleanup());

beforeEach(async () => {
  await db.recursiveDelete(race);
  const users = ["alice", "bob", "carol", "olga", "sam"];
  await Promise.all(users.map((uid) =>
    db.collection("users").doc(uid).set({uid, username: uid})));
  await race.set({
    title: "Run club", description: "", createdBy: "alice",
    participantUids: ["alice", "bob", "carol"],
    organizerUids: ["alice", "olga"],
    status: "active", winCondition: "firstToTarget",
    sharedGoalTitle: "Run", sharedUnit: "km", sharedTargetValue: 100,
    endsAt: admin.firestore.Timestamp.fromMillis(Date.now() + 7 * DAY),
  });
  const progress: Record<string, number> = {alice: 40, bob: 60, carol: 10};
  await Promise.all(Object.entries(progress).map(([uid, value]) =>
    race.collection("participants").doc(uid).set({
      uid, username: uid, goalTitle: "Run", unit: "km", targetValue: 100,
      progress: value, dailyProgress: {[today()]: value},
    })));
});

describe("correctProgress", () => {
  test("writes the total, the day, an entry and an audit record",
    async () => {
      const result = await call(correctProgress, "olga",
        {uid: "bob", progress: 45, reason: "GPS glitch"}) as {
          entryId: string; from: number; to: number;
        };
      assert.equal(result.from, 60);
      assert.equal(result.to, 45);

      const bob = (await race.collection("participants").doc("bob").get())
        .data() ?? {};
      assert.equal(bob.progress, 45);
      assert.equal(bob.dailyProgress[today()], 45);
      assert.equal(bob.lastCorrectionId, result.entryId);

      const entry = (await race.collection("entries").doc(result.entryId)
        .get()).data() ?? {};
      assert.equal(entry.uid, "bob");
      assert.equal(entry.amount, -15);
      assert.deepEqual(entry.source, {type: "organizerCorrection"});
      assert.equal(entry.correction.reason, "GPS glitch");
      assert.equal(entry.correction.byUid, "olga");

      const audit = await race.collection("auditLog").get();
      assert.equal(audit.size, 1);
      const record = audit.docs[0].data();
      assert.equal(record.action, "correctProgress");
      assert.equal(record.actorUid, "olga");
      assert.equal(record.targetUid, "bob");
      assert.deepEqual(record.before, {progress: 60});
      assert.equal(record.after.progress, 45);
      assert.equal(record.reason, "GPS glitch");
      assert.ok(record.at);
    });

  test("only organizers, only with a reason", async () => {
    await refused(call(correctProgress, "bob",
      {uid: "carol", progress: 0, reason: "nope"}), "permission-denied");
    await refused(call(correctProgress, "sam",
      {uid: "carol", progress: 0, reason: "nope"}), "permission-denied");
    await refused(call(correctProgress, "olga",
      {uid: "carol", progress: 0, reason: " "}), "failed-precondition",
    /reason/);
    const audit = await race.collection("auditLog").get();
    assert.equal(audit.size, 0);
  });
});

describe("updateChallengeSettings", () => {
  test("raising the target updates the challenge and every participant",
    async () => {
      await call(updateChallengeSettings, "olga", {targetValue: 150});
      assert.equal((await race.get()).data()?.sharedTargetValue, 150);
      const participants = await race.collection("participants").get();
      assert.deepEqual(
        participants.docs.map((d) => d.data().targetValue), [150, 150, 150]);
      const audit = (await race.collection("auditLog").get()).docs[0].data();
      assert.deepEqual(audit.before, {targetValue: 100});
      assert.deepEqual(audit.after, {targetValue: 150});
    });

  test("lowering the target to someone's progress is refused", async () => {
    await refused(call(updateChallengeSettings, "olga", {targetValue: 60}),
      "failed-precondition", /bob already reached it/);
    assert.equal((await race.get()).data()?.sharedTargetValue, 100);
  });

  test("dates, rules and description change together", async () => {
    const endsAt = Date.now() + 14 * DAY;
    await call(updateChallengeSettings, "alice",
      {endsAtMillis: endsAt, description: "Bring water"});
    const data = (await race.get()).data() ?? {};
    assert.equal(data.endsAt.toMillis(), endsAt);
    assert.equal(data.deadline, new Date(endsAt).toISOString().slice(0, 10));
    assert.equal(data.description, "Bring water");
  });

  test("participants can't edit settings", async () => {
    await refused(call(updateChallengeSettings, "bob", {title: "Mine"}),
      "permission-denied");
  });
});

describe("removeParticipant", () => {
  test("removes them for good, with an audit record", async () => {
    await call(removeParticipant, "olga", {uid: "carol", reason: "Left club"});
    const data = (await race.get()).data() ?? {};
    assert.deepEqual(data.participantUids, ["alice", "bob"]);
    assert.deepEqual(data.removedUids, ["carol"]);
    assert.equal(
      (await race.collection("participants").doc("carol").get()).exists,
      false);
    const audit = (await race.collection("auditLog").get()).docs[0].data();
    assert.equal(audit.action, "removeParticipant");
    assert.equal(audit.reason, "Left club");
  });

  test("a removed participant can't come back through an invite",
    async () => {
      await call(removeParticipant, "olga", {uid: "carol"});
      await db.collection("competition_invites").doc("again").set({
        competitionId: "race", fromUid: "bob", toUid: "carol",
        status: "pending",
      });
      const wrapped = fft.wrap(acceptInvite) as unknown as (
        r: unknown) => Promise<unknown>;
      await refused(wrapped({data: {inviteId: "again"}, auth: {uid: "carol"}}),
        "failed-precondition", /removed you/);
    });
});

describe("endChallengeEarly", () => {
  test("completes it now, furthest along wins, and announces it",
    async () => {
      const result = await call(endChallengeEarly, "olga",
        {reason: "Season over"}) as {winnerUids: string[]};
      assert.deepEqual(result.winnerUids, ["bob"]);
      const data = (await race.get()).data() ?? {};
      assert.equal(data.status, "completed");
      assert.deepEqual(data.winnerUids, ["bob"]);
      assert.equal(data.endedEarly.byUid, "olga");
      assert.ok(data.endsAt.toMillis() <= Date.now());
      const won = await race.collection("events")
        .where("type", "==", "won").get();
      assert.equal(won.size, 1);
      assert.equal(won.docs[0].data().actorUid, "bob");
    });

  test("can't end twice", async () => {
    await call(endChallengeEarly, "olga", {});
    await refused(call(endChallengeEarly, "olga", {}), "failed-precondition",
      /already over/);
  });
});

describe("reinstateParticipant", () => {
  test("overrules an elimination, with a reason, organizers only",
    async () => {
      await race.update({
        winCondition: "lastStanding", rules: {dailyMinimum: 5},
        lastEvaluatedDay: "2026-11-01",
      });
      await race.collection("participants").doc("carol").update({
        eliminatedOnDay: "2026-11-01",
        eliminatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await refused(call(reinstateParticipant, "bob",
        {uid: "carol", reason: "Logged late"}), "permission-denied");
      await refused(call(reinstateParticipant, "olga",
        {uid: "carol", reason: ""}), "failed-precondition", /reason/);

      const result = await call(reinstateParticipant, "olga",
        {uid: "carol", reason: "Logged late"}) as {overruledDay: string};
      assert.equal(result.overruledDay, "2026-11-01");
      const carol = (await race.collection("participants").doc("carol")
        .get()).data() ?? {};
      assert.equal("eliminatedOnDay" in carol, false);
      assert.equal("eliminatedAt" in carol, false);
      const audit = (await race.collection("auditLog").get()).docs[0].data();
      assert.equal(audit.action, "reinstateParticipant");
      assert.deepEqual(audit.before, {eliminatedOnDay: "2026-11-01"});
      assert.equal(audit.reason, "Logged late");

      await refused(call(reinstateParticipant, "olga",
        {uid: "carol", reason: "again"}), "failed-precondition", /still in/);
    });
});

describe("sendAnnouncement", () => {
  test("stores it and puts it in everyone's feed but the sender's",
    async () => {
      const result = await call(sendAnnouncement, "olga",
        {text: "Group run Saturday 7:00"}) as {
          announcementId: string; recipientCount: number;
        };
      assert.equal(result.recipientCount, 3); // alice, bob, carol
      const announcement = (await race.collection("announcements")
        .doc(result.announcementId).get()).data() ?? {};
      assert.equal(announcement.text, "Group run Saturday 7:00");
      assert.equal(announcement.byUid, "olga");

      const events = await race.collection("events")
        .where("type", "==", "announcement").get();
      assert.equal(events.size, 1);
      const event = events.docs[0].data();
      assert.deepEqual([...event.unseenByUserUids].sort(),
        ["alice", "bob", "carol"]);
      assert.equal(event.metadata.text, "Group run Saturday 7:00");
      assert.equal("actorCelebrated" in event, false);
    });

  test("organizers only", async () => {
    await refused(call(sendAnnouncement, "bob", {text: "hi all"}),
      "permission-denied");
  });
});

describe("setOrganizers", () => {
  test("adds and removes co-organizers, never the last one", async () => {
    await call(setOrganizers, "olga", {add: "sam"});
    assert.deepEqual((await race.get()).data()?.organizerUids,
      ["alice", "olga", "sam"]);
    await call(setOrganizers, "sam", {remove: "alice"});
    await call(setOrganizers, "sam", {remove: "olga"});
    await refused(call(setOrganizers, "sam", {remove: "sam"}),
      "failed-precondition", /at least one organizer/);
    // alice is no longer an organizer, but still competes.
    await refused(call(setOrganizers, "alice", {add: "bob"}),
      "permission-denied");
    assert.ok((await race.get()).data()?.participantUids.includes("alice"));
  });

  test("can't add someone who doesn't exist", async () => {
    await refused(call(setOrganizers, "olga", {add: "ghost"}),
      "failed-precondition", /doesn't exist/);
  });
});
