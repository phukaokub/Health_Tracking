import { createHash, randomUUID } from "node:crypto";

import { Upload } from "tus-js-client";

const supabaseURL = required("SUPABASE_URL");
const accessToken = required("TEST_ACCESS_TOKEN");
const apiBaseURL = required("API_BASE_URL");
const source = Buffer.from("synthetic-step-3-tus-probe", "utf8");
const sourceHash = sha256(source);
const sourceReferenceHash = sha256(Buffer.from("synthetic/source/reference", "utf8"));
const pageHash = sha256(Buffer.from("synthetic/page/0", "utf8"));
let importID;

try {
  const created = await api("/api/v1/imports", {
    method: "POST",
    body: JSON.stringify({
      manifest_version: 1,
      source_kind: "directory",
      client_idempotency_key: randomUUID(),
      timezone_candidate: "UTC",
      total_file_count: 1,
      total_logical_bytes: source.byteLength,
      page_content_sha256: pageHash,
      files: [{
        client_file_id: randomUUID(),
        source_reference_hash: sourceReferenceHash,
        source_family: "synthetic-json",
        content_kind: "application/json",
        inclusion_state: "planned",
        logical_bytes: source.byteLength,
        content_sha256: sourceHash,
        parts: [{ part_index: 0, byte_offset: 0, byte_length: source.byteLength, content_sha256: sourceHash }],
      }],
    }),
  });
  importID = created.id;
  const part = created.files[0].parts[0];
  await tusUpload(source, part.object_path, sourceHash);
  const completed = await api(`/api/v1/imports/${importID}/complete`, { method: "POST" });
  if (completed.state !== "queued" || completed.job?.state !== "queued") throw new Error("completion_did_not_queue");
  const deleted = await api(`/api/v1/imports/${importID}`, { method: "DELETE" });
  if (deleted.state !== "deleted") throw new Error("cleanup_did_not_finish");
  importID = undefined;
  process.stdout.write(JSON.stringify({ create: created.state, upload: "verified", complete: completed.state, delete: deleted.state }));
} finally {
  if (importID) await api(`/api/v1/imports/${importID}`, { method: "DELETE" }).catch(() => undefined);
}

function tusUpload(bytes, objectPath, contentSha256) {
  return new Promise((resolve, reject) => {
    const upload = new Upload(bytes, {
      endpoint: `${supabaseURL.replace(/\/$/, "")}/storage/v1/upload/resumable`,
      retryDelays: [0, 3_000, 5_000],
      chunkSize: 6 * 1024 * 1024,
      uploadDataDuringCreation: true,
      removeFingerprintOnSuccess: true,
      headers: { authorization: `Bearer ${accessToken}` },
      metadata: {
        bucketName: "health-imports",
        objectName: objectPath,
        contentType: "application/octet-stream",
        cacheControl: "3600",
        metadata: JSON.stringify({ contentSha256 }),
      },
      onError: () => reject(new Error("tus_upload_failed")),
      onSuccess: resolve,
    });
    upload.start();
  });
}

async function api(path, init) {
  const response = await fetch(new URL(path, `${apiBaseURL.replace(/\/$/, "")}/`), {
    ...init,
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error ?? `api_${response.status}`);
  return body;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`missing_${name.toLowerCase()}`);
  return value;
}
