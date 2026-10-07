import * as assert from "node:assert/strict";
import {test} from "node:test";
import {parseChallenge} from "../model";
import {claimFinish} from "../winConditions/firstToTarget";

const PARTICIPANTS = ["alice", "bob", "carol"];

test("the first finisher wins and is recorded", () => {
  const claim = claimFinish(parseChallenge({}), "alice", PARTICIPANTS, 0);

  assert.equal(claim.position, 1);
  assert.equal(claim.alreadyClaimed, false);
  assert.equal(claim.completes, false);
  assert.deepEqual(claim.update, {
    finisherUids: ["alice"],
    legacyFinisherCount: 0,
    winnerUids: ["alice"],
    winnerUid: "alice",
  });
});

test("a later finisher takes the next position without a new winner", () => {
  const challenge = parseChallenge({
    finisherUids: ["alice"],
    legacyFinisherCount: 0,
    winnerUids: ["alice"],
  });

  // The stale count (0) from outside the transaction is ignored.
  const claim = claimFinish(challenge, "bob", PARTICIPANTS, 0);

  assert.equal(claim.position, 2);
  assert.deepEqual(claim.update, {finisherUids: ["alice", "bob"]});
});

test("a retried trigger for the same finisher claims nothing new", () => {
  const challenge = parseChallenge({
    finisherUids: ["alice", "bob"],
    legacyFinisherCount: 0,
  });

  const claim = claimFinish(challenge, "bob", PARTICIPANTS, 5);

  assert.equal(claim.position, 2);
  assert.equal(claim.alreadyClaimed, true);
  assert.equal(claim.update, null);
});

test("the last finisher completes a race with no deadline", () => {
  const challenge = parseChallenge({
    finisherUids: ["alice", "bob"],
    legacyFinisherCount: 0,
    winnerUids: ["alice"],
  });

  const claim = claimFinish(challenge, "carol", PARTICIPANTS, 2);

  assert.equal(claim.position, 3);
  assert.equal(claim.completes, true);
  assert.equal(claim.update?.status, "completed");
});

test("a race with a deadline is left for the finalizer to complete", () => {
  const challenge = parseChallenge({
    finisherUids: ["alice"],
    legacyFinisherCount: 0,
    endsAt: {toMillis: () => 1},
  });

  const claim = claimFinish(challenge, "bob", ["alice", "bob"], 1);

  assert.equal(claim.completes, false);
  assert.equal(claim.update?.status, undefined);
});

test("a solo participant finishing doesn't complete the challenge", () => {
  const claim = claimFinish(parseChallenge({}), "alice", ["alice"], 0);

  assert.equal(claim.completes, false);
});

test("a legacy race with earlier winners never gets a second winner", () => {
  // Two won/finishedInPosition events exist from before finisherUids.
  const claim = claimFinish(parseChallenge({}), "carol", PARTICIPANTS, 2);

  assert.equal(claim.position, 3);
  assert.deepEqual(claim.update, {
    finisherUids: ["carol"],
    legacyFinisherCount: 2,
  });
  assert.equal(claim.completes, false);
});

test("legacy offset keeps counting after the first claim", () => {
  const challenge = parseChallenge({
    finisherUids: ["carol"],
    legacyFinisherCount: 2,
  });

  const claim = claimFinish(challenge, "dave", [...PARTICIPANTS, "dave"], 3);

  assert.equal(claim.position, 4);
  assert.deepEqual(claim.update, {finisherUids: ["carol", "dave"]});
});
