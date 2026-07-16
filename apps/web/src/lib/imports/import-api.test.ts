import assert from "node:assert/strict";
import test from "node:test";

import { uuidFromSHA256 } from "./identifiers";
import { ImportAPIError, paginateManifestFiles, type ManifestFile } from "./import-api";

test("manifest-derived idempotency UUID changes when reviewed content changes", () => {
  const first = uuidFromSHA256("a".repeat(64));
  const repeated = uuidFromSHA256("a".repeat(64));
  const changed = uuidFromSHA256("b".repeat(64));

  assert.equal(first, repeated);
  assert.notEqual(first, changed);
});

function manifestFile(clientFileID: string, partCount = 1): ManifestFile {
  return {
    client_file_id: clientFileID,
    source_reference_hash: "a".repeat(64),
    source_family: "apple_health",
    content_kind: "xml",
    inclusion_state: "planned",
    logical_bytes: partCount * 20 * 1_024 * 1_024,
    content_sha256: "b".repeat(64),
    parts: Array.from({ length: partCount }, (_, index) => ({
      part_index: index,
      byte_offset: index * 20 * 1_024 * 1_024,
      byte_length: 20 * 1_024 * 1_024,
      content_sha256: "c".repeat(64),
    })),
  };
}

test("manifest pages respect both file-count and encoded-byte limits", () => {
  const files = Array.from({ length: 1_001 }, (_, index) => manifestFile(String(index)));
  const countPages = paginateManifestFiles(files, 10 * 1_024 * 1_024);
  assert.deepEqual(countPages.map((page) => page.length), [1_000, 1]);

  const bytePages = paginateManifestFiles([
    manifestFile("first", 4),
    manifestFile("second", 4),
  ], 1_300);
  assert.deepEqual(bytePages.map((page) => page.length), [1, 1]);
  for (const page of bytePages) {
    assert.ok(new TextEncoder().encode(JSON.stringify(page)).byteLength <= 1_300);
  }
});

test("a single manifest file larger than the safe page budget is rejected", () => {
  assert.throws(
    () => paginateManifestFiles([manifestFile("too-large", 4)], 500),
    (error) => error instanceof ImportAPIError
      && error.code === "manifest_file_metadata_too_large"
      && error.status === 413,
  );
});
