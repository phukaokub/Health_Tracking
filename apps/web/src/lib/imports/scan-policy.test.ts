import assert from "node:assert/strict";
import test from "node:test";

import { classifySourcePath, isSafeZipEntry, normalizeRelativePath } from "./scan-policy";

test("scanner policy normalizes relative paths and rejects traversal", () => {
  assert.equal(normalizeRelativePath("Huawei\\Health\\records.json"), "Huawei/Health/records.json");
  assert.equal(normalizeRelativePath("../records.json"), null);
  assert.equal(normalizeRelativePath("C:/records.json"), null);
  assert.equal(normalizeRelativePath("/records.json"), null);
});

test("scanner policy classifies JSON and legacy spreadsheets without raw path output", () => {
  assert.deepEqual(classifySourcePath("export/records.json"), {
    sourceFamily: "huawei-json",
    contentKind: "application/json",
    included: true,
  });
  assert.equal(classifySourcePath("export/history.xls").sourceFamily, "legacy-xls");
  assert.equal(classifySourcePath("export/readme.txt").included, false);
});

test("scanner policy rejects zip-bomb-like ratios and unsafe entries", () => {
  assert.equal(isSafeZipEntry("export/records.json", 1_000_000, 20_000), true);
  assert.equal(isSafeZipEntry("export/records.json", 1_000_000, 1_000), false);
  assert.equal(isSafeZipEntry("../../records.json", 10, 10), false);
});
