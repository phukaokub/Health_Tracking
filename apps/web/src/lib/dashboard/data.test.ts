import { strict as assert } from "node:assert";
import test from "node:test";

import { latestImportedWindow } from "./data";

test("latest imported window is capped at the report maximum", () => {
  assert.deepEqual(latestImportedWindow({ start_date: "2026-03-07", end_date: "2026-07-06" }), {
    start_date: "2026-04-08",
    end_date: "2026-07-06",
  });
});

test("latest imported window keeps shorter available histories intact", () => {
  assert.deepEqual(latestImportedWindow({ start_date: "2026-06-01", end_date: "2026-07-06" }), {
    start_date: "2026-06-01",
    end_date: "2026-07-06",
  });
});

test("latest imported window returns null when no canonical data range exists", () => {
  assert.equal(latestImportedWindow({ start_date: null, end_date: null }), null);
});
