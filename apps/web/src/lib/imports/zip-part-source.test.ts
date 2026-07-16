import assert from "node:assert/strict";
import test from "node:test";

import { zipSync } from "fflate";

import type { ImportFilePlan } from "./import-api";
import { sha256Text, uuidFromSHA256 } from "./identifiers";
import { streamVerifiedZIPParts } from "./zip-part-source";

async function digest(value: Uint8Array): Promise<string> {
  const copy = Uint8Array.from(value);
  const result = await crypto.subtle.digest("SHA-256", copy.buffer);
  return [...new Uint8Array(result)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

test("ZIP source streams expected immutable parts without retaining the archive", async () => {
  const path = "export/records.json";
  const bytes = new TextEncoder().encode("synthetic-zip-part-source");
  const first = bytes.slice(0, 9);
  const second = bytes.slice(9);
  const file: ImportFilePlan = {
    id: crypto.randomUUID(),
    client_file_id: uuidFromSHA256(await sha256Text(path)),
    inclusion_state: "planned",
    logical_bytes: bytes.byteLength,
    content_sha256: await digest(bytes),
    content_kind: "application/json",
    source_family: "huawei-json",
    parts: [
      { id: crypto.randomUUID(), part_index: 0, byte_offset: 0, byte_length: first.byteLength, content_sha256: await digest(first), object_path: "part-0", state: "planned" },
      { id: crypto.randomUUID(), part_index: 1, byte_offset: first.byteLength, byte_length: second.byteLength, content_sha256: await digest(second), object_path: "part-1", state: "planned" },
    ],
  };
  const received: string[] = [];
  await streamVerifiedZIPParts(new Blob([zipSync({ [path]: bytes })]), [file], async (_file, part, blob) => {
    assert.equal(await digest(new Uint8Array(await blob.arrayBuffer())), part.content_sha256);
    received.push(part.object_path);
  });
  assert.deepEqual(received, ["part-0", "part-1"]);
});

test("ZIP source rejects a selection that no longer matches the reviewed manifest", async () => {
  const bytes = new TextEncoder().encode("changed");
  await assert.rejects(
    () => streamVerifiedZIPParts(new Blob([zipSync({ "export/records.json": bytes })]), [], async () => undefined),
    /source_archive_changed/,
  );
});
