import assert from "node:assert/strict";
import test from "node:test";

import { strToU8, zipSync } from "fflate";

import { scanZipArchive } from "./zip-scan";

test("ZIP scanner streams a synthetic archive and returns only safe metadata", async () => {
  const archive = zipSync({ "export/records.json": strToU8('{"synthetic":true}') });
  const result = await scanZipArchive(new Blob([archive]), () => false);

  assert.equal(result.warnings.length, 0);
  assert.equal(result.files.length, 1);
  assert.equal(result.files[0]?.sourceFamily, "huawei-json");
  assert.match(result.files[0]?.contentSha256 ?? "", /^[0-9a-f]{64}$/);
  assert.match(result.files[0]?.sourceReferenceHash ?? "", /^[0-9a-f]{64}$/);
});

test("ZIP scanner rejects traversal metadata without returning a path", async () => {
  const archive = zipSync({ "../private.json": strToU8('{"synthetic":true}') });
  const result = await scanZipArchive(new Blob([archive]), () => false);

  assert.equal(result.files.length, 0);
  assert.deepEqual(result.warnings, [{ code: "unsafe_zip_entry" }]);
});

test("ZIP scanner rejects an empty archive and stops before a cancelled scan reads bytes", async () => {
  await assert.rejects(scanZipArchive(new Blob([zipSync({})]), () => false), /unsafe_zip_entry/);
  await assert.rejects(scanZipArchive(new Blob([zipSync({ "export/records.json": strToU8("{}") })]), () => true), /scan_cancelled/);
});
