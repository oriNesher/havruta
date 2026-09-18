import * as assert from "node:assert/strict";
import {test} from "node:test";
import {ONBOARDING_VERSION, SYSTEM_USER_UID} from "../config";
import {
  ONBOARDING_SYSTEM_PROGRESS,
  challengeFriendsProblem,
  decideRespectGrant,
  decideSystemProgress,
  isSystemOnboardingProgressEvent,
} from "../eventsRespect";

const UID = "alice";

const competition = (overrides: Record<string, unknown> = {}) => ({
  createdBy: SYSTEM_USER_UID,
  status: "active",
  participantUids: [SYSTEM_USER_UID, UID],
  onboarding: {
    isOnboarding: true,
    onboardingUserId: UID,
    onboardingChallengeKey: "challengeFriends",
    onboardingVersion: ONBOARDING_VERSION,
  },
  ...overrides,
});
const systemParticipant = {uid: SYSTEM_USER_UID, progress: 0};
const callerParticipant = {uid: UID, progress: 0};

// ── Authorization / metadata validation ──────────────────────────────────

test("accepts the caller's own, correctly tagged Challenge B", () => {
  assert.equal(
    challengeFriendsProblem(
      UID, competition(), systemParticipant, callerParticipant
    ),
    null
  );
});

test("rejects a missing Challenge B", () => {
  assert.notEqual(
    challengeFriendsProblem(
      UID, undefined, systemParticipant, callerParticipant
    ),
    null
  );
});

test("rejects another user's onboarding challenge", () => {
  assert.notEqual(
    challengeFriendsProblem(
      "mallory", competition(), systemParticipant,
      {uid: "mallory", progress: 0}
    ),
    null
  );
});

test("rejects a challenge that only has the right title", () => {
  assert.notEqual(
    challengeFriendsProblem(
      UID,
      competition({onboarding: undefined}),
      systemParticipant,
      callerParticipant
    ),
    null
  );
});

test("rejects Challenge A (wrong onboarding key)", () => {
  const c = competition();
  c.onboarding.onboardingChallengeKey = "acceptInvites";
  assert.notEqual(
    challengeFriendsProblem(UID, c, systemParticipant, callerParticipant),
    null
  );
});

test("rejects a stale onboarding version", () => {
  const c = competition();
  c.onboarding.onboardingVersion = ONBOARDING_VERSION - 1;
  assert.notEqual(
    challengeFriendsProblem(UID, c, systemParticipant, callerParticipant),
    null
  );
});

test("rejects a challenge not owned by the system user", () => {
  assert.notEqual(
    challengeFriendsProblem(
      UID, competition({createdBy: UID}), systemParticipant, callerParticipant
    ),
    null
  );
});

test("rejects a system participant doc that isn't the system user", () => {
  assert.notEqual(
    challengeFriendsProblem(
      UID, competition(), {uid: "impostor", progress: 0}, callerParticipant
    ),
    null
  );
});

test("rejects a caller who hasn't joined Challenge B", () => {
  assert.notEqual(
    challengeFriendsProblem(
      UID,
      competition({participantUids: [SYSTEM_USER_UID]}),
      systemParticipant,
      undefined
    ),
    null
  );
});

test("rejects an inactive Challenge B", () => {
  assert.notEqual(
    challengeFriendsProblem(
      UID,
      competition({status: "completed"}),
      systemParticipant,
      callerParticipant
    ),
    null
  );
});

// ── System progress idempotency ──────────────────────────────────────────

test("applies Havruta's progress the first time", () => {
  assert.equal(decideSystemProgress(undefined, systemParticipant), "apply");
});

test("never re-applies once the ledger records it (retry/relaunch)", () => {
  assert.equal(
    decideSystemProgress(
      {systemProgressAppliedAt: {seconds: 1}},
      systemParticipant
    ),
    "alreadyApplied"
  );
});

test("never re-applies once Havruta already shows the progress", () => {
  assert.equal(
    decideSystemProgress(undefined, {
      uid: SYSTEM_USER_UID,
      progress: ONBOARDING_SYSTEM_PROGRESS,
    }),
    "alreadyApplied"
  );
});

test("repeated calls converge: apply once, then alreadyApplied", () => {
  // Simulates the transaction's effect between two sequential calls.
  let participant = {...systemParticipant};
  let ledger: Record<string, unknown> | undefined;
  for (let i = 0; i < 5; i++) {
    if (decideSystemProgress(ledger, participant) === "apply") {
      participant = {...participant, progress: participant.progress + 1};
      ledger = {systemProgressAppliedAt: {seconds: i}};
    }
  }
  assert.equal(participant.progress, ONBOARDING_SYSTEM_PROGRESS);
});

// ── Onboarding Respect grant ─────────────────────────────────────────────

const grantInput = {
  balance: 0,
  ledgerRespectGrant: undefined,
  systemProgressApplied: true,
  alreadyGaveRespect: false,
};

test("grants when the balance is empty and nothing was claimed", () => {
  assert.equal(decideRespectGrant(grantInput), "grant");
});

test("does not grant when the user already has Respect", () => {
  assert.equal(
    decideRespectGrant({...grantInput, balance: 1}),
    "notNeeded"
  );
});

test("never grants twice, even with an empty balance again", () => {
  assert.equal(
    decideRespectGrant({
      ...grantInput,
      ledgerRespectGrant: {grantedAt: {seconds: 1}},
    }),
    "alreadyGranted"
  );
});

test("does not grant before Havruta's onboarding progress exists", () => {
  assert.equal(
    decideRespectGrant({...grantInput, systemProgressApplied: false}),
    "systemProgressNotApplied"
  );
});

test("does not grant after the tutorial Respect was already given", () => {
  assert.equal(
    decideRespectGrant({...grantInput, alreadyGaveRespect: true}),
    "alreadyGaveRespect"
  );
});

// ── Identifying Havruta's onboarding event ───────────────────────────────

test("matches Havruta's first progress event", () => {
  assert.equal(
    isSystemOnboardingProgressEvent({
      type: "progress",
      actorUid: SYSTEM_USER_UID,
      metadata: {beforeProgress: 0, afterProgress: 1},
    }),
    true
  );
});

test("ignores the user's own events and Havruta's other event types", () => {
  assert.equal(
    isSystemOnboardingProgressEvent({
      type: "progress",
      actorUid: UID,
      metadata: {beforeProgress: 0},
    }),
    false
  );
  assert.equal(
    isSystemOnboardingProgressEvent({
      type: "firstBlood",
      actorUid: SYSTEM_USER_UID,
      metadata: {},
    }),
    false
  );
});

test("ignores a later Havruta progress event (not the 0 -> 1 one)", () => {
  assert.equal(
    isSystemOnboardingProgressEvent({
      type: "progress",
      actorUid: SYSTEM_USER_UID,
      metadata: {beforeProgress: 1, afterProgress: 2},
    }),
    false
  );
});
