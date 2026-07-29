import { createHash, randomBytes, randomUUID } from "node:crypto";
import { readFile, unlink, writeFile } from "node:fs/promises";

import { createClient } from "@supabase/supabase-js";

const phase = process.argv[2];
const statePath = process.env.STEP4_E2E_STATE_PATH;
const supabaseURL = process.env.STEP4_E2E_SUPABASE_URL;
const publishableKey = process.env.STEP4_E2E_PUBLISHABLE_KEY;
const apiBaseURL = process.env.STEP4_E2E_API_BASE_URL;

if (!phase || !statePath || !supabaseURL || !publishableKey || !apiBaseURL) {
  throw new Error("staging_e2e_configuration_invalid");
}

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const safeError = (code, error) => {
  const status = Number(error?.status ?? 0);
  const providerCode = String(error?.code ?? "unknown").replace(/[^a-z0-9_]/gi, "_").slice(0, 80);
  throw new Error(`${code}:${status}:${providerCode}`);
};
const output = (value) => process.stdout.write(`${JSON.stringify(value)}\n`);

function client() {
  return createClient(supabaseURL, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
}

async function readState() {
  return JSON.parse(await readFile(statePath, "utf8"));
}

async function writeState(state) {
  await writeFile(statePath, JSON.stringify(state), { encoding: "utf8", mode: 0o600 });
}

async function signIn(state) {
  const supabase = client();
  const { data, error } = await supabase.auth.signInWithPassword({
    email: state.email,
    password: state.password,
  });
  if (error || !data.session?.access_token) safeError("signin_failed", error);
  return { supabase, accessToken: data.session.access_token };
}

async function api(path, accessToken, init = {}) {
  const response = await fetch(new URL(path, `${apiBaseURL.replace(/\/$/, "")}/`), {
    ...init,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
      ...init.headers,
    },
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`staging_api_failed:${response.status}:${String(payload.error ?? "unknown")}`);
  }
  return payload;
}

async function setup() {
  const suffix = randomUUID();
  // A UUID-sized local part makes this a non-personal, unreachable synthetic
  // address while satisfying hosted Auth's public-domain validation.
  const email = `step4-e2e-${suffix}@gmail.com`;
  const password = `${randomBytes(30).toString("base64url")}Aa1!`;
  const supabase = client();
  const { data, error } = await supabase.auth.signUp({ email, password });
  if (error || !data.user?.id) safeError("signup_failed", error);
  await writeState({ email, password, userID: data.user.id });
  output({ phase: "signup_created", user_id: data.user.id, session_created: Boolean(data.session) });
}

function syntheticSource() {
  return Buffer.from(JSON.stringify({
    records: [
      {
        type: "heart_rate", record_id: "synthetic-hosted-heart",
        started_at: "2026-01-02T03:04:05Z", unit: "bpm", value: 72,
      },
      {
        type: "sleep_session", record_id: "synthetic-hosted-sleep",
        started_at: "2026-01-02T00:00:00Z", ended_at: "2026-01-02T02:00:00Z",
        stages: [
          { code: "deep", started_at: "2026-01-02T00:00:00Z", ended_at: "2026-01-02T01:00:00Z" },
          { code: "light", started_at: "2026-01-02T01:00:00Z", ended_at: "2026-01-02T02:00:00Z" },
        ],
      },
      {
        type: "activity", record_id: "synthetic-hosted-activity", activity_type: "walking",
        started_at: "2026-01-02T04:00:00Z", ended_at: "2026-01-02T04:10:00Z",
        route: [{ lat: 0, lon: 0 }],
      },
      {
        type: "workout_summary", record_id: "synthetic-hosted-workout", workout_type: "running",
        started_at: "2026-01-02T05:00:00Z", ended_at: "2026-01-02T05:30:00Z",
        distance_metres: 5000, energy_kilocalories: 300,
        route: [{ lat: 0, lon: 0 }],
      },
      {
        type: "ecg", record_id: "synthetic-hosted-ecg",
        started_at: "2026-01-02T06:00:00Z", unit: "summary", value: 1,
        waveform: [1, 2], rri: [3, 4],
      },
      {
        type: "workout_route", record_id: "synthetic-hosted-route",
        started_at: "2026-01-02T07:00:00Z", unit: "summary", value: 1,
        route: [{ lat: 0, lon: 0 }],
      },
    ],
  }));
}

async function queueImport() {
  const state = await readState();
  const { supabase, accessToken } = await signIn(state);
  const source = syntheticSource();
  const contentSHA256 = sha256(source);
  const file = {
    client_file_id: randomUUID(),
    source_reference_hash: sha256("synthetic-hosted-huawei-json"),
    source_family: "huawei_health_json",
    content_kind: "application/json",
    inclusion_state: "planned",
    logical_bytes: source.length,
    content_sha256: contentSHA256,
    parts: [{
      part_index: 0,
      byte_offset: 0,
      byte_length: source.length,
      content_sha256: contentSHA256,
    }],
  };
  const manifest = {
    manifest_version: 1,
    source_kind: "directory",
    client_idempotency_key: randomUUID(),
    timezone_candidate: "UTC",
    total_file_count: 1,
    total_logical_bytes: source.length,
    page_content_sha256: sha256(JSON.stringify([file])),
    files: [file],
  };
  const created = await api("/api/v1/imports", accessToken, {
    method: "POST",
    body: JSON.stringify(manifest),
  });
  const part = created.files?.[0]?.parts?.[0];
  if (!created.id || !part?.object_path) throw new Error("manifest_snapshot_invalid");

  const { error: uploadError } = await supabase.storage
    .from("health-imports")
    .upload(part.object_path, source, {
      contentType: "application/octet-stream",
      upsert: false,
      metadata: { contentSha256: contentSHA256 },
    });
  if (uploadError) safeError("storage_upload_failed", uploadError);

  const queued = await api(`/api/v1/imports/${created.id}/complete`, accessToken, { method: "POST" });
  if (queued.state !== "queued") throw new Error("import_did_not_queue");
  await writeState({ ...state, importID: created.id, objectPath: part.object_path });
  output({ phase: "queued", user_id: state.userID, import_id: created.id, total_file_count: 1, object_count: 1 });
}

async function canonicalCounts(supabase, importID) {
  const tables = [
    "health_samples", "normalization_provenance", "sleep_sessions",
    "sleep_stages", "activities", "workout_sessions",
  ];
  const counts = {};
  for (const table of tables) {
    const query = supabase.from(table).select("*", { count: "exact", head: true });
    const scoped = table === "sleep_stages" ? query : query.eq("import_id", importID);
    const { count, error } = await scoped;
    if (error) safeError("canonical_count_failed", error);
    counts[table] = count ?? 0;
  }
  return counts;
}

async function verifyProcessed() {
  const state = await readState();
  const { supabase, accessToken } = await signIn(state);
  const snapshot = await api(`/api/v1/imports/${state.importID}`, accessToken, { method: "GET" });
  const counts = await canonicalCounts(supabase, state.importID);
  const { data: objectInfo, error: objectError } = await supabase.storage
    .from("health-imports")
    .info(state.objectPath);
  const warnings = snapshot.job?.warning_codes ?? [];
  if (
    snapshot.state !== "completed_with_warnings" ||
    snapshot.job?.processed_file_count !== 1 ||
    snapshot.job?.normalized_record_count !== 6 ||
    !warnings.includes("sensitive_record_excluded") ||
    counts.health_samples !== 1 ||
    counts.normalization_provenance !== 1 ||
    counts.sleep_sessions !== 1 ||
    counts.sleep_stages !== 2 ||
    counts.activities !== 1 ||
    counts.workout_sessions !== 1 ||
    objectError ||
    !objectInfo
  ) {
    throw new Error("processed_import_acceptance_failed");
  }
  output({
    phase: "processed",
    user_id: state.userID,
    import_id: state.importID,
    state: snapshot.state,
    processed_file_count: snapshot.job.processed_file_count,
    normalized_record_count: snapshot.job.normalized_record_count,
    warning_codes: warnings,
    canonical_counts: counts,
    raw_object_retained: true,
  });
}

async function verifyCleanupAndDelete() {
  const state = await readState();
  const { supabase, accessToken } = await signIn(state);
  const { data: objectInfo, error: objectError } = await supabase.storage
    .from("health-imports")
    .info(state.objectPath);
  if (!objectError || objectInfo) throw new Error("raw_object_cleanup_failed");

  const retainedCounts = await canonicalCounts(supabase, state.importID);
  if (
    retainedCounts.health_samples !== 1 ||
    retainedCounts.sleep_sessions !== 1 ||
    retainedCounts.sleep_stages !== 2 ||
    retainedCounts.activities !== 1 ||
    retainedCounts.workout_sessions !== 1
  ) {
    throw new Error("canonical_rows_removed_with_raw_source");
  }

  const deleted = await api(`/api/v1/imports/${state.importID}`, accessToken, { method: "DELETE" });
  if (deleted.state !== "deleted") throw new Error("import_delete_failed");
  const deletedCounts = await canonicalCounts(supabase, state.importID);
  if (Object.values(deletedCounts).some((count) => count !== 0)) {
    throw new Error("canonical_delete_did_not_converge");
  }
  await unlink(statePath);
  output({
    phase: "cleanup_and_delete_complete",
    user_id: state.userID,
    import_id: state.importID,
    raw_object_present: false,
    canonical_rows_retained_until_owner_delete: true,
    canonical_rows_after_owner_delete: 0,
  });
}

if (phase === "setup") await setup();
else if (phase === "queue") await queueImport();
else if (phase === "verify") await verifyProcessed();
else if (phase === "cleanup") await verifyCleanupAndDelete();
else throw new Error("staging_e2e_phase_invalid");
