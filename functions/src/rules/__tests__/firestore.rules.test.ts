// Emulator tests for firestore.rules — allowed and denied cases for every
// role. Run with `npm run test:rules` (needs Java for the emulator); not
// part of `npm run test`, which stays emulator-free.
//
// Cast, all against the "race" challenge unless noted:
// - alice: its creator, a participant and an organizer
// - bob:   a participant
// - eve:   a participant who has been eliminated
// - olga:  an organizer who doesn't compete
// - ivan:  holds a pending direct invite, hasn't joined
// - sam:   a signed-in stranger
import {after, before, beforeEach, describe, test} from "node:test";
import {readFileSync} from "fs";
import {resolve} from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  arrayUnion,
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  increment,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
} from "firebase/firestore";

let env: RulesTestEnvironment;

const inAWeek = () => Timestamp.fromMillis(Date.now() + 7 * 864e5);

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-havruta-rules",
    firestore: {
      rules: readFileSync(
        resolve(__dirname, "../../../../firestore.rules"),
        "utf8"
      ),
    },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const set = (path: string, data: Record<string, unknown>) =>
      setDoc(doc(db, path), data);

    await set("users/alice", {
      uid: "alice", username: "Alice", usernameLower: "alice",
      email: "alice@example.com", emailLower: "alice@example.com",
      fcmTokens: ["token-a"], respectBalance: 3,
    });
    await set("users/bob", {uid: "bob", username: "Bob"});
    await set("publicProfiles/alice", {
      uid: "alice", username: "Alice", usernameLower: "alice",
    });

    await set("competitions/race", {
      title: "Run club", description: "", createdBy: "alice",
      participantUids: ["alice", "bob", "eve"],
      organizerUids: ["alice", "olga"],
      status: "active", winCondition: "firstToTarget",
      sharedGoalTitle: "Run", sharedUnit: "km", sharedTargetValue: 100,
      endsAt: inAWeek(),
    });
    for (const uid of ["alice", "bob"]) {
      await set(`competitions/race/participants/${uid}`, {
        uid, username: uid, goalTitle: "Run", unit: "km",
        targetValue: 100, progress: 10,
      });
    }
    await set("competitions/race/participants/eve", {
      uid: "eve", username: "eve", progress: 0, eliminatedOnDay: "2026-11-01",
    });
    await set("competitions/race/entries/bobFix", {
      uid: "bob", amount: -5, source: {type: "organizerCorrection"},
      status: "counted",
    });
    await set("competitions/race/auditLog/a1", {
      action: "correctProgress", actorUid: "olga", targetUid: "bob",
    });
    await set("competitions/race/events/e1", {
      type: "progress", competitionId: "race", actorUid: "bob",
      unseenByUserUids: ["alice"], actorCelebrated: false,
    });

    // Predates organizerUids: run by its creator alone.
    await set("competitions/legacy", {
      title: "Old", createdBy: "alice", participantUids: ["alice", "bob"],
      status: "active", type: "personalGoalChallenge",
    });
    await set("competitions/legacy/participants/bob", {
      uid: "bob", goalTitle: "Read", targetValue: 20, progress: 0,
    });

    await set("competitions/done", {
      title: "Done", createdBy: "alice", participantUids: ["alice", "bob"],
      status: "completed", winCondition: "mostProgress",
    });
    await set("competitions/done/participants/bob", {uid: "bob", progress: 3});

    await set("competition_invites/inv1", {
      competitionId: "race", fromUid: "alice", toUid: "ivan",
      status: "pending",
    });
    await set("challenge_invite_links/link1", {competitionId: "race"});
  });
});

const as = (uid: string) => env.authenticatedContext(uid).firestore();
const anonymous = () => env.unauthenticatedContext().firestore();

describe("users", () => {
  test("only the owner can read their doc (email, push tokens)", async () => {
    await assertSucceeds(getDoc(doc(as("alice"), "users/alice")));
    await assertFails(getDoc(doc(as("bob"), "users/alice")));
    await assertFails(getDoc(doc(anonymous(), "users/alice")));
    await assertFails(getDocs(query(collection(as("sam"), "users"),
      where("emailLower", "==", "alice@example.com"))));
  });

  test("the owner writes cosmetic fields but never the wallet", async () => {
    const ref = doc(as("alice"), "users/alice");
    await assertSucceeds(updateDoc(ref, {streakCount: 4}));
    await assertSucceeds(updateDoc(ref, {fcmTokens: arrayUnion("token-b")}));
    await assertFails(updateDoc(ref, {respectBalance: 999}));
    await assertFails(updateDoc(ref, {totalRespectReceived: 50}));
    await assertFails(updateDoc(ref, {respectLastGrantDate: "2099-01-01"}));
  });

  test("registration can't seed a wallet; nobody writes others", async () => {
    await assertSucceeds(setDoc(doc(as("sam"), "users/sam"),
      {uid: "sam", username: "Sam"}));
    await assertFails(setDoc(doc(as("dan"), "users/dan"),
      {uid: "dan", username: "Dan", respectBalance: 100}));
    await assertFails(updateDoc(doc(as("bob"), "users/alice"),
      {username: "hacked"}));
  });
});

describe("publicProfiles", () => {
  test("signed-in users can look people up by username", async () => {
    await assertSucceeds(getDoc(doc(as("sam"), "publicProfiles/alice")));
    await assertSucceeds(getDocs(query(collection(as("sam"), "publicProfiles"),
      where("usernameLower", "==", "alice"))));
    await assertFails(getDoc(doc(anonymous(), "publicProfiles/alice")));
  });

  test("nobody writes them, not even the owner", async () => {
    await assertFails(setDoc(doc(as("alice"), "publicProfiles/alice"),
      {uid: "alice", username: "Queen"}));
    await assertFails(setDoc(doc(as("sam"), "publicProfiles/sam"),
      {uid: "sam", username: "Sam"}));
  });
});

describe("competitions: read", () => {
  test("participants and organizers can read the challenge", async () => {
    await assertSucceeds(getDoc(doc(as("bob"), "competitions/race")));
    await assertSucceeds(getDoc(doc(as("olga"), "competitions/race")));
    await assertSucceeds(getDoc(doc(as("eve"), "competitions/race")));
  });

  test("strangers, invitees and signed-out users can't", async () => {
    await assertFails(getDoc(doc(as("sam"), "competitions/race")));
    await assertFails(getDoc(doc(as("ivan"), "competitions/race")));
    await assertFails(getDoc(doc(anonymous(), "competitions/race")));
  });

  test("Home's my-challenges query works, others' doesn't", async () => {
    await assertSucceeds(getDocs(query(collection(as("bob"), "competitions"),
      where("participantUids", "array-contains", "bob"))));
    await assertFails(getDocs(query(collection(as("sam"), "competitions"),
      where("participantUids", "array-contains", "bob"))));
    await assertFails(getDocs(collection(as("sam"), "competitions")));
  });

  test("a deleted challenge reads as missing, not denied", async () => {
    const snap = await assertSucceeds(
      getDoc(doc(as("bob"), "competitions/gone")));
    if (snap.exists()) throw new Error("expected no document");
  });
});

describe("competitions: create, update, delete", () => {
  const newChallenge = (extra: Record<string, unknown> = {}) => ({
    title: "New", description: "", createdBy: "dan",
    participantUids: ["dan"], status: "active", winnerUid: null,
    winCondition: "mostProgress", ...extra,
  });

  test("a user creates a challenge seeded with only themselves", async () => {
    const db = as("dan");
    await assertSucceeds(setDoc(doc(db, "competitions/new"), newChallenge()));
    await assertSucceeds(setDoc(doc(db, "competitions/new/participants/dan"),
      {uid: "dan", username: "Dan", progress: 0}));
  });

  test("creation can't seed others, organizers, or outcomes", async () => {
    const db = as("dan");
    await assertFails(setDoc(doc(db, "competitions/c1"),
      newChallenge({participantUids: ["dan", "bob"]})));
    await assertFails(setDoc(doc(db, "competitions/c2"),
      newChallenge({organizerUids: ["dan", "sam"]})));
    await assertFails(setDoc(doc(db, "competitions/c3"),
      newChallenge({winnerUids: ["dan"]})));
    await assertFails(setDoc(doc(db, "competitions/c4"),
      newChallenge({createdBy: "bob"})));
  });

  test("organizers rename; participants and strangers can't", async () => {
    await assertSucceeds(updateDoc(doc(as("olga"), "competitions/race"),
      {title: "Run club 2"}));
    await assertSucceeds(updateDoc(doc(as("alice"), "competitions/legacy"),
      {description: "creator of a pre-organizer challenge"}));
    await assertFails(updateDoc(doc(as("bob"), "competitions/race"),
      {title: "mine now"}));
    await assertFails(updateDoc(doc(as("bob"), "competitions/legacy"),
      {title: "mine now"}));
  });

  test("nobody can add themselves to a challenge", async () => {
    await assertFails(updateDoc(doc(as("sam"), "competitions/race"),
      {participantUids: arrayUnion("sam")}));
    await assertFails(updateDoc(doc(as("ivan"), "competitions/race"),
      {participantUids: arrayUnion("ivan")}));
    // The pre-callable accept-invite batch older builds still send.
    const db = as("ivan");
    const batch = writeBatch(db);
    batch.update(doc(db, "competitions/race"),
      {participantUids: arrayUnion("ivan")});
    batch.set(doc(db, "competitions/race/participants/ivan"),
      {uid: "ivan", progress: 0});
    batch.update(doc(db, "competition_invites/inv1"), {status: "accepted"});
    await assertFails(batch.commit());
  });

  test("the definition and outcome are fixed once created", async () => {
    await assertFails(updateDoc(doc(as("alice"), "competitions/race"),
      {sharedTargetValue: 1}));
    await assertFails(updateDoc(doc(as("alice"), "competitions/race"),
      {winnerUids: ["alice"]}));
    await assertFails(updateDoc(doc(as("alice"), "competitions/race"),
      {organizerUids: ["alice", "olga", "sam"]}));
  });

  test("only the creator deletes a challenge", async () => {
    await assertFails(deleteDoc(doc(as("bob"), "competitions/race")));
    await assertFails(deleteDoc(doc(as("sam"), "competitions/race")));
    await assertSucceeds(deleteDoc(doc(as("alice"), "competitions/race")));
  });
});

describe("organizers", () => {
  const organized = (extra: Record<string, unknown> = {}) => ({
    title: "Club run", description: "", createdBy: "olga",
    participantUids: [], organizerUids: ["olga"], status: "active",
    winnerUid: null, winCondition: "mostProgress", ...extra,
  });

  test("an organizer can create a challenge without competing", async () => {
    await assertSucceeds(
      setDoc(doc(as("olga"), "competitions/club"), organized()));
    // ...and it shows up in their organizer query.
    await assertSucceeds(getDocs(query(collection(as("olga"), "competitions"),
      where("organizerUids", "array-contains", "olga"))));
  });

  test("organizing without competing still needs organizerUids", async () => {
    const withoutOrganizers: Record<string, unknown> = organized();
    delete withoutOrganizers.organizerUids;
    await assertFails(setDoc(doc(as("olga"), "competitions/c1"),
      withoutOrganizers));
    await assertFails(setDoc(doc(as("olga"), "competitions/c2"),
      organized({organizerUids: ["sam"]})));
  });

  test("creation can't seed removals or an early end", async () => {
    await assertFails(setDoc(doc(as("olga"), "competitions/c3"),
      organized({removedUids: ["bob"]})));
    await assertFails(setDoc(doc(as("olga"), "competitions/c4"),
      organized({endedEarly: {byUid: "olga"}})));
  });

  test("nobody else can query someone's organized challenges", async () => {
    await assertFails(getDocs(query(collection(as("sam"), "competitions"),
      where("organizerUids", "array-contains", "olga"))));
  });

  test("organizer powers aren't direct writes", async () => {
    const challenge = doc(as("olga"), "competitions/race");
    await assertFails(updateDoc(challenge, {endsAt: inAWeek()}));
    await assertFails(updateDoc(challenge, {status: "completed"}));
    await assertFails(updateDoc(challenge,
      {removedUids: arrayUnion("bob")}));
    await assertFails(deleteDoc(challenge));
  });

  test("entries: the participant's own and the organizers' only", async () => {
    const path = "competitions/race/entries/bobFix";
    await assertSucceeds(getDoc(doc(as("bob"), path)));
    await assertSucceeds(getDoc(doc(as("olga"), path)));
    await assertSucceeds(getDoc(doc(as("alice"), path)));
    await assertFails(getDoc(doc(as("eve"), path)));
    await assertFails(getDoc(doc(as("sam"), path)));
    await assertSucceeds(getDocs(query(
      collection(as("bob"), "competitions/race/entries"),
      where("uid", "==", "bob"))));
    await assertFails(getDocs(
      collection(as("bob"), "competitions/race/entries")));
    await assertSucceeds(getDocs(
      collection(as("olga"), "competitions/race/entries")));
  });

  test("nobody writes entries directly yet", async () => {
    await assertFails(setDoc(
      doc(as("bob"), "competitions/race/entries/mine"),
      {uid: "bob", amount: 1000}));
    await assertFails(updateDoc(
      doc(as("olga"), "competitions/race/entries/bobFix"), {amount: 0}));
  });

  test("the audit log is organizer-only and read-only", async () => {
    await assertSucceeds(getDocs(
      collection(as("olga"), "competitions/race/auditLog")));
    await assertFails(getDocs(
      collection(as("bob"), "competitions/race/auditLog")));
    await assertFails(getDoc(
      doc(as("sam"), "competitions/race/auditLog/a1")));
    await assertFails(updateDoc(
      doc(as("olga"), "competitions/race/auditLog/a1"), {reason: "edited"}));
    await assertFails(deleteDoc(
      doc(as("olga"), "competitions/race/auditLog/a1")));
  });

  test("a participant can't pass off a write as a correction", async () => {
    await assertFails(updateDoc(
      doc(as("bob"), "competitions/race/participants/bob"),
      {progress: 50, lastCorrectionId: "fake"}));
  });
});

describe("participants", () => {
  test("members read the standings; strangers can't", async () => {
    await assertSucceeds(getDocs(
      collection(as("bob"), "competitions/race/participants")));
    await assertSucceeds(getDocs(
      collection(as("olga"), "competitions/race/participants")));
    await assertFails(getDocs(
      collection(as("sam"), "competitions/race/participants")));
    await assertFails(getDoc(
      doc(as("ivan"), "competitions/race/participants/bob")));
  });

  test("you can't create a participant doc without being let in", async () => {
    await assertFails(setDoc(
      doc(as("sam"), "competitions/race/participants/sam"),
      {uid: "sam", progress: 0}));
  });

  test("a new participant doc starts from zero, own uid only", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), "competitions/race"),
        {participantUids: arrayUnion("dan")});
    });
    const db = as("dan");
    await assertFails(setDoc(doc(db, "competitions/race/participants/dan"),
      {uid: "dan", progress: 500}));
    await assertFails(setDoc(doc(db, "competitions/race/participants/dan"),
      {uid: "dan", progress: 0, eliminatedOnDay: null}));
    await assertFails(setDoc(doc(db, "competitions/race/participants/bob"),
      {uid: "bob", progress: 0}));
    await assertSucceeds(setDoc(doc(db, "competitions/race/participants/dan"),
      {uid: "dan", progress: 0}));
  });

  test("a participant logs and lowers their own progress", async () => {
    const ref = doc(as("bob"), "competitions/race/participants/bob");
    await assertSucceeds(updateDoc(ref,
      {progress: increment(5), updatedAt: serverTimestamp()}));
    await assertSucceeds(updateDoc(ref,
      {progress: 2, updatedAt: serverTimestamp()}));
  });

  test("nobody writes someone else's progress — organizers neither",
    async () => {
      await assertFails(updateDoc(
        doc(as("bob"), "competitions/race/participants/alice"),
        {progress: 0}));
      await assertFails(updateDoc(
        doc(as("olga"), "competitions/race/participants/bob"),
        {progress: 99}));
      await assertFails(updateDoc(
        doc(as("sam"), "competitions/race/participants/bob"),
        {progress: 0}));
    });

  test("a shared goal's target can't be edited by a participant", async () => {
    const ref = doc(as("bob"), "competitions/race/participants/bob");
    await assertFails(updateDoc(ref, {targetValue: 1}));
    await assertFails(updateDoc(ref, {goalTitle: "Walk"}));
  });

  test("a legacy personal participant still edits their own goal",
    async () => {
      await assertSucceeds(updateDoc(
        doc(as("bob"), "competitions/legacy/participants/bob"),
        {targetValue: 30, goalTitle: "Read more"}));
    });

  test("progress can't go negative or be a non-number", async () => {
    const ref = doc(as("bob"), "competitions/race/participants/bob");
    await assertFails(updateDoc(ref, {progress: -1}));
    await assertFails(updateDoc(ref, {progress: "lots"}));
  });

  test("server-owned fields stay server-owned", async () => {
    const ref = doc(as("bob"), "competitions/race/participants/bob");
    await assertFails(updateDoc(ref, {currentStreak: 100}));
    await assertFails(updateDoc(ref, {eliminatedOnDay: "2026-11-02"}));
  });

  test("no progress once eliminated or once the challenge is over",
    async () => {
      await assertFails(updateDoc(
        doc(as("eve"), "competitions/race/participants/eve"),
        {progress: 1}));
      await assertFails(updateDoc(
        doc(as("bob"), "competitions/done/participants/bob"),
        {progress: 4}));
    });

  test("no client deletes any participant doc", async () => {
    await assertFails(deleteDoc(
      doc(as("sam"), "competitions/race/participants/bob")));
    await assertFails(deleteDoc(
      doc(as("bob"), "competitions/race/participants/alice")));
    await assertFails(deleteDoc(
      doc(as("alice"), "competitions/race/participants/bob")));
    await assertFails(deleteDoc(
      doc(as("bob"), "competitions/race/participants/bob")));
  });
});

describe("events", () => {
  test("members read a challenge's activity; strangers can't", async () => {
    await assertSucceeds(getDocs(
      collection(as("alice"), "competitions/race/events")));
    await assertSucceeds(getDocs(
      collection(as("olga"), "competitions/race/events")));
    await assertFails(getDocs(
      collection(as("sam"), "competitions/race/events")));
  });

  test("the celebrations query sees only the caller's own events",
    async () => {
      await assertSucceeds(getDocs(query(collectionGroup(as("bob"), "events"),
        where("actorUid", "==", "bob"),
        where("actorCelebrated", "==", false))));
      await assertFails(getDocs(query(collectionGroup(as("sam"), "events"),
        where("actorUid", "==", "bob"))));
      await assertFails(getDocs(collectionGroup(as("sam"), "events")));
    });

  test("dismissing and celebrating are the only client writes", async () => {
    await assertSucceeds(updateDoc(
      doc(as("alice"), "competitions/race/events/e1"),
      {unseenByUserUids: []}));
    await assertSucceeds(updateDoc(
      doc(as("bob"), "competitions/race/events/e1"),
      {actorCelebrated: true}));
    await assertFails(setDoc(
      doc(as("bob"), "competitions/race/events/fake"),
      {type: "won", actorUid: "bob"}));
    await assertFails(deleteDoc(
      doc(as("alice"), "competitions/race/events/e1")));
  });
});

describe("competition_invites", () => {
  test("recipient, sender and members can see an invite", async () => {
    await assertSucceeds(getDocs(query(
      collection(as("ivan"), "competition_invites"),
      where("toUid", "==", "ivan"), where("status", "==", "pending"))));
    await assertSucceeds(getDoc(doc(as("alice"), "competition_invites/inv1")));
    await assertSucceeds(getDocs(query(
      collection(as("bob"), "competition_invites"),
      where("competitionId", "==", "race"),
      where("status", "==", "pending"))));
  });

  test("strangers can't see a challenge's invites", async () => {
    await assertFails(getDoc(doc(as("sam"), "competition_invites/inv1")));
    await assertFails(getDocs(query(
      collection(as("sam"), "competition_invites"),
      where("competitionId", "==", "race"))));
  });

  test("members invite others; strangers can't invite into it", async () => {
    await assertSucceeds(setDoc(doc(as("bob"), "competition_invites/inv2"),
      {competitionId: "race", fromUid: "bob", toUid: "sam",
        status: "pending"}));
    await assertFails(setDoc(doc(as("sam"), "competition_invites/inv3"),
      {competitionId: "race", fromUid: "sam", toUid: "dan",
        status: "pending"}));
    await assertFails(setDoc(doc(as("bob"), "competition_invites/inv4"),
      {competitionId: "race", fromUid: "alice", toUid: "sam",
        status: "pending"}));
  });

  test("a recipient can decline but not self-accept", async () => {
    const ref = doc(as("ivan"), "competition_invites/inv1");
    await assertFails(updateDoc(ref, {status: "accepted"}));
    await assertSucceeds(updateDoc(ref, {status: "declined"}));
    await assertFails(updateDoc(doc(as("sam"), "competition_invites/inv1"),
      {status: "declined"}));
  });

  test("the sender or an organizer withdraws an invite", async () => {
    await assertFails(deleteDoc(doc(as("sam"), "competition_invites/inv1")));
    await assertFails(deleteDoc(doc(as("bob"), "competition_invites/inv1")));
    await assertSucceeds(
      deleteDoc(doc(as("olga"), "competition_invites/inv1")));
  });
});

describe("invite links", () => {
  test("stay entirely server-side", async () => {
    await assertFails(getDoc(doc(as("alice"), "challenge_invite_links/link1")));
    await assertFails(setDoc(doc(as("alice"), "challenge_invite_links/x"),
      {competitionId: "race"}));
  });
});

describe("unlisted collections", () => {
  test("progress cursors and anything else default to denied", async () => {
    await assertFails(getDoc(
      doc(as("alice"), "competitions/race/progressCursors/bob")));
    await assertFails(setDoc(doc(as("alice"), "somethingNew/x"), {a: 1}));
  });
});
