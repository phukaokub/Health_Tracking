import assert from "node:assert/strict";
import test from "node:test";

import { markDuplicateFiles } from "./deduplicate";
import type { ScannedFile } from "./scanner.types";

function plannedFile(clientFileId: string, contentSha256: string, logicalBytes = 10): ScannedFile {
  return {
    clientFileId,
    contentKind: "application/json",
    contentSha256,
    duplicateOfClientFileId: null,
    inclusionState: "planned",
    logicalBytes,
    parts: [{ byteLength: logicalBytes, byteOffset: 0, contentSha256, partIndex: 0 }],
    sourceFamily: "huawei-json",
    sourceReferenceHash: "b".repeat(64),
  };
}

test("duplicate detection keeps the first exact file and skips later matches", () => {
  const hash = "a".repeat(64);
  const result = markDuplicateFiles([plannedFile("first", hash), plannedFile("second", hash)]);

  assert.equal(result[0]?.inclusionState, "planned");
  assert.equal(result[1]?.inclusionState, "skipped_duplicate");
  assert.equal(result[1]?.duplicateOfClientFileId, "first");
  assert.deepEqual(result[1]?.parts, []);
});

test("duplicate detection does not collapse same hash metadata with a different byte length", () => {
  const hash = "a".repeat(64);
  const result = markDuplicateFiles([plannedFile("first", hash, 10), plannedFile("second", hash, 11)]);

  assert.deepEqual(result.map((file) => file.inclusionState), ["planned", "planned"]);
});
