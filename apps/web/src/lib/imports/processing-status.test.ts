import test from "node:test";
import assert from "node:assert/strict";

import type { ImportSnapshot } from "./import-api";
import { processingProgress, processingRecordCount, processingWarningCodes, warningLabel } from "./processing-status";

const snapshot = (overrides: Partial<ImportSnapshot> = {}): ImportSnapshot => ({
  id: "10000000-0000-4000-8000-000000000001",
  state: "processing",
  total_file_count: 4,
  total_logical_bytes: 123,
  files: [],
  ...overrides,
});

test("processing status exposes bounded owner-safe progress", () => {
  assert.equal(processingProgress(snapshot({ job: { id: "job", state: "processing", job_type: "parse_import", processed_file_count: 2 } })), 50);
  assert.equal(processingProgress(snapshot({ job: { id: "job", state: "processing", job_type: "parse_import", processed_file_count: 9 } })), 100);
  assert.equal(processingProgress(snapshot({ total_file_count: 0 })), null);
});

test("processing status prefers job counts and stable warning codes", () => {
  const value = snapshot({
    job: { id: "job", state: "completed_with_warnings", job_type: "parse_import", normalized_record_count: 7, warning_codes: ["route_content_dropped"] },
    normalization: { normalized_record_count: 2, warning_codes: ["json_truncated"] },
  });
  assert.equal(processingRecordCount(value), 7);
  assert.deepEqual(processingWarningCodes(value), ["route_content_dropped"]);
  assert.match(warningLabel("route_content_dropped"), /privacy/i);
  assert.match(warningLabel("unrecognized_safe_code"), /skipped/i);
});
