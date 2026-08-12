import * as assert from "node:assert/strict";
import {test} from "node:test";
import {
  shouldCreateJoinedEvent,
  shouldCreateLeftEvent,
} from "../rules/lifecycle";

test("does not create a joined event for the creator's own seeded doc", () => {
  assert.equal(shouldCreateJoinedEvent("alice", "alice"), false);
});

test("creates a joined event for any other participant doc", () => {
  assert.equal(shouldCreateJoinedEvent("bob", "alice"), true);
});

test("creates a joined event when the competition has no known creator", () => {
  assert.equal(shouldCreateJoinedEvent("bob", undefined), true);
});

test("creates a left event when the competition still exists", () => {
  assert.equal(shouldCreateLeftEvent(true), true);
});

test("does not create a left event when the competition is gone too", () => {
  assert.equal(shouldCreateLeftEvent(false), false);
});
