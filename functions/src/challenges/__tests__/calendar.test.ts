import * as assert from "node:assert/strict";
import {test} from "node:test";
import {addDays, challengeDayKey, daysBetween} from "../calendar";

test("without a time zone, days are UTC dates", () => {
  // 2026-10-06T22:30Z
  assert.equal(challengeDayKey(Date.UTC(2026, 9, 6, 22, 30), null),
    "2026-10-06");
});

test("a challenge's day follows its own time zone", () => {
  // 22:30 UTC is already 01:30 the next day in Jerusalem (UTC+3 in Oct).
  const moment = Date.UTC(2026, 9, 6, 22, 30);
  assert.equal(challengeDayKey(moment, "Asia/Jerusalem"), "2026-10-07");
  // ...and still the afternoon before in New York.
  assert.equal(challengeDayKey(moment, "America/New_York"), "2026-10-06");
});

test("an unknown time zone falls back to UTC", () => {
  assert.equal(
    challengeDayKey(Date.UTC(2026, 9, 6, 22, 30), "Not/AZone"),
    "2026-10-06"
  );
});

test("day arithmetic crosses months and DST without drifting", () => {
  assert.equal(addDays("2026-10-31", 1), "2026-11-01");
  assert.equal(addDays("2026-03-01", -1), "2026-02-28");
  // US DST ends 2026-11-01; whole-date math is unaffected.
  assert.equal(addDays("2026-10-31", 2), "2026-11-02");
  assert.equal(daysBetween("2026-10-30", "2026-11-02"), 3);
});
