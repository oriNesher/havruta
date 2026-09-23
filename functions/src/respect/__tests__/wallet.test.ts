import * as assert from "node:assert/strict";
import {test} from "node:test";
import {RESPECT_WALLET_CAPACITY, decideDailyGrant} from "../wallet";

const TODAY = "2026-09-18";
const YESTERDAY = "2026-09-17";

test("new user starts the clock with an empty wallet", () => {
  assert.deepEqual(
    decideDailyGrant({balance: 0, lastGrantDate: undefined, today: TODAY}),
    {balance: 0, write: true}
  );
});

test("grants one Respect on a new day", () => {
  assert.deepEqual(
    decideDailyGrant({balance: 2, lastGrantDate: YESTERDAY, today: TODAY}),
    {balance: 3, write: true}
  );
});

test("already granted today is a no-op", () => {
  assert.deepEqual(
    decideDailyGrant({balance: 2, lastGrantDate: TODAY, today: TODAY}),
    {balance: 2, write: false}
  );
});

test("fills the last slot up to capacity", () => {
  assert.deepEqual(
    decideDailyGrant({
      balance: RESPECT_WALLET_CAPACITY - 1,
      lastGrantDate: YESTERDAY,
      today: TODAY,
    }),
    {balance: RESPECT_WALLET_CAPACITY, write: true}
  );
});

test("full wallet forfeits the day's grant", () => {
  assert.deepEqual(
    decideDailyGrant({
      balance: RESPECT_WALLET_CAPACITY,
      lastGrantDate: YESTERDAY,
      today: TODAY,
    }),
    {balance: RESPECT_WALLET_CAPACITY, write: true}
  );
});

test("legacy balance over capacity is kept, not trimmed", () => {
  assert.deepEqual(
    decideDailyGrant({balance: 9, lastGrantDate: YESTERDAY, today: TODAY}),
    {balance: 9, write: true}
  );
});
