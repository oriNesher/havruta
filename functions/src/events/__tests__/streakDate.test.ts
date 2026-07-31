import * as assert from "node:assert/strict";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {isNextCalendarDay, toDateString} from "../streakDate";

test("toDateString formats a timestamp as a UTC calendar date", () => {
  const timestamp = Timestamp.fromDate(new Date("2026-03-05T23:30:00Z"));

  assert.equal(toDateString(timestamp), "2026-03-05");
});

test("isNextCalendarDay is true for consecutive days", () => {
  assert.equal(isNextCalendarDay("2026-03-05", "2026-03-06"), true);
});

test("isNextCalendarDay is true across a month boundary", () => {
  assert.equal(isNextCalendarDay("2026-02-28", "2026-03-01"), true);
});

test("isNextCalendarDay is false for the same day", () => {
  assert.equal(isNextCalendarDay("2026-03-05", "2026-03-05"), false);
});

test("isNextCalendarDay is false when a day was skipped", () => {
  assert.equal(isNextCalendarDay("2026-03-05", "2026-03-07"), false);
});
