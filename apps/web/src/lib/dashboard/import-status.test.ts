import { strict as assert } from "node:assert";
import test from "node:test";

import { isImportPending } from "./data";

test("queued imports are marked pending", () => {
  assert.equal(isImportPending({ state: "queued", job_state: "queued" }), true);
});

test("completed imports are not marked pending", () => {
  assert.equal(isImportPending({ state: "completed_with_warnings", job_state: "completed" }), false);
});

test("an active job remains pending when the run state is stale", () => {
  assert.equal(isImportPending({ state: "completed", job_state: "processing" }), true);
});

test("missing import status is not marked pending", () => {
  assert.equal(isImportPending(null), false);
});
