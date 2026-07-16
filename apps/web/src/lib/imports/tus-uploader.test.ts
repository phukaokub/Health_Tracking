import assert from "node:assert/strict";
import test from "node:test";

import { deriveTUSEndpoint, TUS_TRANSPORT_CHUNK_BYTES } from "./tus-uploader";

test("TUS endpoint uses the direct hosted Storage origin and fixed 6 MiB chunks", () => {
  assert.equal(
    deriveTUSEndpoint("https://project-ref.supabase.co"),
    "https://project-ref.storage.supabase.co/storage/v1/upload/resumable",
  );
  assert.equal(TUS_TRANSPORT_CHUNK_BYTES, 6 * 1024 * 1024);
});

test("TUS endpoint keeps local Supabase on its local origin", () => {
  assert.equal(
    deriveTUSEndpoint("http://127.0.0.1:54321"),
    "http://127.0.0.1:54321/storage/v1/upload/resumable",
  );
});
