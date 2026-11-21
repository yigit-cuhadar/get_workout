import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  addDays,
  dayAt,
  daysOf,
  endingAt,
  isDay,
  lengthOf,
  mondayOf,
  previousOf,
  suffixOf,
} from "./dates";

describe("dates", () => {
  test("isDay takes only real YYYY-MM-DD days", () => {
    assert.ok(isDay("2026-02-28"));
    assert.ok(isDay("2028-02-29"));
    for (const value of [
      "2026-02-29",
      "2026-13-01",
      "2026-1-01",
      "",
      20261101,
      null,
    ]) {
      assert.ok(!isDay(value), String(value));
    }
  });

  test("day arithmetic crosses months and years", () => {
    assert.equal(addDays("2026-12-31", 1), "2027-01-01");
    assert.equal(addDays("2026-03-01", -1), "2026-02-28");
    assert.equal(lengthOf({ from: "2026-11-01", to: "2026-11-01" }), 1);
    assert.equal(lengthOf({ from: "2026-01-01", to: "2026-12-31" }), 365);
    assert.deepEqual(daysOf({ from: "2026-10-30", to: "2026-11-02" }), [
      "2026-10-30",
      "2026-10-31",
      "2026-11-01",
      "2026-11-02",
    ]);
  });

  test("the previous range is equally long and ends the day before", () => {
    assert.deepEqual(previousOf({ from: "2026-11-14", to: "2026-11-20" }), {
      from: "2026-11-07",
      to: "2026-11-13",
    });
    assert.deepEqual(endingAt("2026-11-20", 30), {
      from: "2026-10-22",
      to: "2026-11-20",
    });
  });

  test("weeks start on Monday", () => {
    assert.equal(mondayOf("2026-11-16"), "2026-11-16");
    assert.equal(mondayOf("2026-11-22"), "2026-11-16");
    assert.equal(mondayOf("2026-11-23"), "2026-11-23");
  });

  test("table suffix and the day in a zone", () => {
    assert.equal(suffixOf("2026-11-05"), "20261105");
    const lateUtc = Date.UTC(2026, 10, 20, 22, 30);
    assert.equal(dayAt(lateUtc, "UTC"), "2026-11-20");
    assert.equal(dayAt(lateUtc, "Europe/Istanbul"), "2026-11-21");
  });
});
