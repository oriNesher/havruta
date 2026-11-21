// Emulator replay of the client's create-challenge flow, write for write
// (FirestoreService.createChallenge), plus the reads the screens that
// open right after it make. Run with `npm run test:rules`.
import {after, before, beforeEach, describe, test} from "node:test";
import {readFileSync} from "fs";
import {resolve} from "path";
import {
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  addDoc,
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} from "firebase/firestore";

let env: RulesTestEnvironment;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-havruta-create",
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
    await setDoc(doc(ctx.firestore(), "users/dan"), {
      uid: "dan", username: "Dan", usernameLower: "dan",
      respectBalance: 3, respectLastGrantDate: "2026-11-19",
    });
  });
});

const flows: Array<[string, Record<string, unknown>, boolean]> = [
  ["race, creator competes", {
    winCondition: "firstToTarget", sharedTargetValue: 100,
  }, true],
  ["most progress with an end date and a prize", {
    winCondition: "mostProgress",
    endsAt: Timestamp.fromMillis(Date.now() + 7 * 864e5),
    deadline: "2026-11-27",
    prize: "Pizza",
  }, true],
  ["last one standing", {
    winCondition: "lastStanding",
    rules: {dailyMinimum: 10},
    startsAt: Timestamp.fromMillis(Date.now()),
  }, true],
  ["organizing without competing", {
    winCondition: "mostProgress",
    endsAt: Timestamp.fromMillis(Date.now() + 7 * 864e5),
  }, false],
];

describe("create-challenge flow, as the client runs it", () => {
  for (const [name, extra, competes] of flows) {
    test(name, async () => {
      const db = env.authenticatedContext("dan").firestore();

      // getMyUsername
      await assertSucceeds(getDoc(doc(db, "users/dan")));

      const ref = await assertSucceeds(addDoc(collection(db, "competitions"), {
        title: "New", description: "", createdBy: "dan",
        participantUids: competes ? ["dan"] : [],
        organizerUids: ["dan"],
        status: "active", winnerUid: null,
        type: "sharedGoalChallenge",
        sharedGoalTitle: "Run", sharedUnit: "km",
        timeZone: "Asia/Jerusalem",
        createdAt: serverTimestamp(),
        ...extra,
      }));

      const path = `competitions/${ref.id}`;
      if (competes) {
        const target = extra.sharedTargetValue;
        await assertSucceeds(setDoc(doc(db, `${path}/participants/dan`), {
          uid: "dan", username: "Dan", goalTitle: "Run",
          ...(target ? {targetValue: target} : {}),
          unit: "km", progress: 0,
          joinedAt: serverTimestamp(), updatedAt: serverTimestamp(),
        }));
      }

      await assertSucceeds(updateDoc(doc(db, "users/dan"), {
        lastCompetitionCreatedAt: serverTimestamp(),
      }));

      // What Home and the invite screen read next.
      await assertSucceeds(getDocs(query(collection(db, "competitions"),
        where("organizerUids", "array-contains", "dan"))));
      await assertSucceeds(getDocs(query(collection(db, "competitions"),
        where("participantUids", "array-contains", "dan"))));
      await assertSucceeds(getDoc(doc(db, path)));
      await assertSucceeds(getDocs(collection(db, `${path}/participants`)));
      await assertSucceeds(getDocs(query(collection(db, "competition_invites"),
        where("competitionId", "==", ref.id),
        where("status", "==", "pending"))));
      await assertSucceeds(getDocs(collection(db, `${path}/events`)));
    });
  }
});
