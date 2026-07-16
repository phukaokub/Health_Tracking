# Change plan: Step 4 Huawei JSON normalization

## Metadata

- Change ID: STEP-004
- Milestone/work packages: Step 4 / 4A-4J
- Owner: repository maintainer with Codex implementation support
- Status: proposed; local parser work may begin only after the Step 3 job/Storage contract is accepted, and hosted worker execution remains gated
- Baseline commit: `b79d63ef3cbf85d9584234d7d92802d26d9b2112` (PR #9 merge)
- Branch: `codex/step-4-plan`
- Related records: [`../IMPLEMENTATION_STEPS.md`](../IMPLEMENTATION_STEPS.md), [`../DELIVERY_TRACKER.md`](../DELIVERY_TRACKER.md), [`0004-source-coverage-matrix.md`](0004-source-coverage-matrix.md), ADR 0005 (proposed)
- Target environments: local, CI, stable staging; production is explicitly excluded
- Last updated: 2026-07-17

## Outcome

A queued, owner-scoped import is parsed incrementally from immutable private Storage parts into canonical wellness records with deterministic dedupe, provenance, retry-safe checkpoints, and actionable redacted warnings. Raw source payloads, ECG waveform/RRI samples, and GPS routes are not persisted.

### Success measures

- A generated export containing every approved source family produces the same normalized snapshot on repeated runs and after retry from a checkpoint.
- Peak resident memory stays below 256 MiB for the generated 72 MiB single-file fixture and does not grow with total export size.
- Each transaction writes at most 1,000 canonical rows and completes within 5 seconds in local/staging measurements; both limits are constants with tests.
- A duplicate import or overlapping Huawei batch produces zero duplicate canonical rows while recording provenance/checkpoint completion.
- Every normalized row has `user_id`, `import_id`, `import_file_id`, parser/schema version, deterministic dedupe key, source-family code, and resolved timezone provenance.
- Malformed motion JSON is repaired only for decimal keys inside `paceMap`, `paceMapNative`, or `partTimeMap`; all other malformed syntax fails with a stable safe code.
- Raw payload text, metric values, source paths/names, email, JWTs, worker credentials, ECG waveform/RRI data, and GPS points never appear in database errors, application logs, screenshots, or CI artifacts.
- A staging synthetic job can lose its lease mid-file, resume at a validated checkpoint, complete once, and release/delete temporary source parts according to the accepted retention rule.

### Non-goals

- Legacy XLS parsing or JSON-versus-XLS precedence (Step 5).
- Dashboard aggregation, goals, scores, forecasts, or suggestions (Steps 6-7).
- Raw ECG interpretation, waveform/RRI persistence, diagnosis, treatment, or medical predictions.
- Default GPS route storage or map rendering.
- Production worker/provider provisioning or production data migration.
- A generic ETL platform, arbitrary JSON repair, or user-authored parser plugins.

## User and failure flows

### Happy path

1. Step 3 queues one `parse_import` job after all expected objects are verified.
2. A worker claims one eligible job with an expiring lease and immutable parser version.
3. The worker streams ordered Storage parts, validates part metadata, identifies the parser from the approved source family, and emits bounded canonical batches.
4. A transaction upserts canonical rows by owner/dedupe key, records provenance and warnings, and advances a checkpoint only after the batch commits.
5. The worker renews the lease between batches, marks each file complete, then marks the job/import completed or completed-with-warnings.
6. Raw source objects become cleanup-eligible after successful verification/retention; no raw payload is copied into Postgres.

### Failure and recovery

- Missing/tampered part: stop before parsing, record `source_part_invalid`, keep the job retryable only when the object may be transiently unavailable.
- Truncated JSON or unsupported schema: mark the file failed with a stable code and bounded context containing no payload excerpt.
- Lease expiry/process death: another worker may claim after expiry and resume only from the last committed token/batch checkpoint.
- Duplicate delivery: claim and persistence RPCs are idempotent; one job and one canonical row per dedupe key survive.
- Batch failure: roll back the entire batch and leave the prior checkpoint unchanged.
- Cancellation/deletion: lease renewal fails, the worker stops before the next batch, and cleanup cannot delete objects under a current valid lease.
- Provider outage/429/5xx: bounded exponential backoff with jitter; release or expire the lease, never spin indefinitely.
- Parser regression: disable worker trigger, leave queued jobs intact, roll back worker code, and use a forward migration for schema correction.

### Acceptance scenarios

1. Given the generated all-family fixture, when parsed twice, then canonical snapshots and row counts are byte-for-byte stable and no duplicates are added.
2. Given a crash after batch N commits, when a new worker resumes, then it starts at checkpoint N and produces the same final result as an uninterrupted run.
3. Given malformed decimal motion-map keys only in approved fields, when parsed, then keys are repaired and a warning count is recorded without storing route points.
4. Given malformed syntax outside approved motion-map fields, when parsed, then the file fails with `motion_json_invalid` and no partial batch survives.
5. Given a worker or user from another owner, when requesting a lease, object, checkpoint, or normalized row, then access is denied without revealing existence.
6. Given cancellation during processing, when the lease is revoked, then the worker stops within one batch and later cleanup is convergent.

## Scope and impact matrix

| Area | Change? | Detail / owning work package |
| --- | --- | --- |
| Next.js UI/routes/server actions | Yes | Read-only import processing/progress/warning state in 4I; no payload rendering |
| Go API/domain/repository | Yes | Parser registry, streaming decoder, worker loop, canonical types, lease/checkpoint clients in 4A/4D/4F |
| OpenAPI/client contract | Yes | Owner progress/warning response additions only; worker endpoints are internal and separately authenticated |
| Postgres schema/index/grant/RLS | Yes | Canonical tables, provenance, job lease/checkpoint RPCs, dedupe indexes, owner reads, worker-only writes in 4C/4F |
| Supabase Auth/JWT | Yes | Proposed dedicated worker identity/claim; no browser privilege expansion (ADR 0005) |
| Supabase Storage/policies | Yes | Worker read only for parts belonging to its active lease; no list-all or overwrite permission |
| Background jobs/cron | Yes | Bounded one-job/one-slice worker invocation, lease renewal, retries, dead-letter state |
| Third-party provider console | Yes | Staging worker runtime/trigger and Supabase worker identity; production deferred |
| Environment variables/secrets | Yes | Worker trigger and identity secrets; exact inventory below, no values |
| Logging/metrics/alerts | Yes | Redacted job/file/batch timings and counts; no values or payload excerpts |
| Privacy/retention/deletion | Yes | Normalized-only persistence, prohibited ECG/GPS content, raw-part cleanup coordination |
| Documentation/support | Yes | Mapping matrix, ADR, parser runbook, warning/error catalog, staging evidence |

## Dependencies and decisions

| Item | Type | Owner | Needed by | State / default |
| --- | --- | --- | --- | --- |
| Step 3 hosted acceptance | dependency | Product/release owner | 4F hosted worker | Required; local 4A-4E may proceed after job contract acceptance |
| ADR 0005 worker runtime/access | decision | Engineering + security owner | 4F | Proposed; dedicated non-browser worker identity is preferred, broad service-role access rejected by default |
| Mapping/exclusion matrix | product/privacy decision | Product owner | 4B/4D | Proposed in companion matrix; explicit user approval required |
| JSON streaming library | dependency | Engineering | 4A | Prefer Go standard `encoding/json.Decoder`; add no library unless benchmark or token repair proves it necessary |
| Motion tokenizer | dependency/design | Engineering | 4E | Custom narrow state machine; no general malformed-JSON library |
| Queue/trigger | provider decision | Engineering/release owner | 4F/4H | Existing `import_jobs` is source of truth; Supabase Queue adoption requires a separate measured migration |
| Worker runtime ceiling | limit | Engineering/release owner | 4F | Target 240-second slice; benchmark at 180 seconds and 192 MiB to preserve headroom |
| Batch size | limit | Engineering | 4C/4D | Start at 1,000 rows and 4 MiB encoded parameter cap; lower based on staging latency |
| Raw-part retention | privacy decision | Product/security owner | 4H | Delete after successful parse plus accepted recovery window; exact hours approved before hosted enablement |

## Design and contracts

### Parser boundary

```text
ordered immutable Storage parts
  -> checksum/length verifying reader
  -> source-family registry
  -> streaming token decoder / narrow motion repair
  -> canonical records + safe warnings
  -> bounded transactional persistence
  -> committed checkpoint + lease renewal
```

The parser package is pure with respect to provider APIs: it consumes `io.Reader`, emits typed records/warnings, and accepts cancellation. Storage, leases, and Postgres persistence are adapters. This allows generated fixtures to test parsing without Supabase or network access.

### Canonical schema proposal

- `devices`: owner-scoped stable device fingerprint/hash and sanitized model/source category; no advertising IDs or raw serial numbers.
- `health_samples`: scalar timestamp/range metrics such as heart rate, resting heart rate, HRV, stress, skin temperature, SpO2, steps, calories, distance, floors, intensity, active duration.
- `daily_health_summaries`: one owner/day/timezone summary with source coverage flags; JSON sources only in Step 4.
- `sleep_sessions` and `sleep_stages`: session bounds, duration, stage code, confidence/quality when explicitly present and approved.
- `activities`: non-route activity intervals and canonical counts/durations.
- `workout_sessions`: workout summary fields; no GPS polyline/points by default.
- `ecg_sessions`: session timestamp/duration/device and source summary status only; no waveform or RRI columns.
- `parser_file_checkpoints`: file/part/byte/token position, committed batch sequence, parser version, lease generation, and completion state.

Every canonical table has `id`, `user_id`, `import_id`, `import_file_id`, `dedupe_key`, `source_family`, `source_record_id_hash` when available, `parser_version`, `created_at`, and required temporal/unit fields. `dedupe_key` is a SHA-256 over a versioned canonical identity tuple, not raw JSON. Unique constraints use `(user_id, dedupe_key)` and do not include parser version.

### Time and unit rules

1. Explicit source UTC offset wins.
2. Otherwise use an approved device/export offset when unambiguous.
3. Otherwise resolve with the import timezone candidate/profile IANA timezone and record `timezone_resolution = profile_fallback`.
4. Ambiguous/nonexistent local times produce warnings; no silent shift beyond the documented resolver.

Canonical units: count, seconds, metres, kilocalories, bpm, milliseconds, degrees Celsius, percent, and source-scale stress/intensity codes. Conversion is decimal-safe and tested at boundaries; source unit code and conversion version are retained as provenance, not raw payload.

### Lease and checkpoint state

- Claim is atomic and uses `FOR UPDATE SKIP LOCKED`, changing `queued` or expired `leased/processing` to `leased`, incrementing `attempt_count`, assigning a random lease generation, and setting `lease_expires_at`.
- Only the same worker subject and lease generation can renew, persist a batch, checkpoint, complete, or fail the job.
- A checkpoint advances in the same transaction as its canonical batch; it points only to a token boundary that can be replayed deterministically.
- After the maximum retry count, the job becomes `failed` with a non-retryable safe code; there is no infinite retry loop.
- Completion is idempotent and changes the import to `completed` or `completed_with_warnings` only after all planned files are terminal.

### Stable error taxonomy

`source_part_invalid`, `source_object_unavailable`, `source_schema_unsupported`, `json_truncated`, `json_depth_exceeded`, `json_token_too_large`, `motion_json_invalid`, `motion_repair_out_of_scope`, `metric_mapping_unknown`, `unit_unsupported`, `timestamp_invalid`, `batch_persist_failed`, `lease_lost`, `job_cancelled`, `worker_timeout`, and `worker_configuration_invalid`.

Errors expose retryability and safe detail from an allowlist. They never include source path/name, JSON token text, metric value, email, object URL, or credential.

### Data lifecycle

- Data created: normalized records, provenance hashes, checkpoints, counts, warning/error codes.
- Data read: verified private part objects and owner/job metadata.
- Owner key: `user_id` inherited from the claimed import; callers never supply a different owner to persistence RPCs.
- Retention: canonical wellness data persists until import/data/account deletion; source parts follow the accepted short recovery window.
- Deletion: import deletion cancels lease, deletes canonical rows by import/owner, then removes source objects and metadata idempotently.
- Backfill/reconciliation: parser version upgrades run as explicit new jobs and upsert by stable dedupe key; silent mass rewrite is prohibited.

### Migration plan

- `4C` expand migration creates canonical/checkpoint tables, indexes, grants, RLS, and no worker writes yet.
- `4F` adds reviewed claim/renew/persist/complete/fail RPCs and narrowly scoped Storage read policy after ADR 0005 acceptance.
- Existing API/web remain compatible while no worker trigger is enabled.
- Run clean local reset, schema lint, pgTAP, advisors, generated load fixture, then staging migration and rollback compatibility smoke.
- Migrations are expand-only. Rollback disables the worker trigger and reverts code; schema removal requires a later contract migration.
- Stop on long locks, cross-owner visibility, direct browser writes, unexpected Storage listing, or any raw payload persistence.

## Environment and secret delta

No value may be placed in source, chat, logs, screenshots, or PR text.

| Variable/credential | Class | Consumer | Local | Staging | Production | Store/owner | Rotation trigger |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `WORKER_TRIGGER_SECRET` | Secret | Internal worker HTTP trigger | Generated local-only value | Vercel encrypted env + scheduler caller | Deferred | Release owner | Exposure, staff/offboarding, incident |
| `SUPABASE_WORKER_IDENTITY` | Internal/sensitive | Worker login identifier | Synthetic worker account | Dedicated staging Auth account | Deferred | Vercel encrypted env; Auth admin owner | Account change/offboarding |
| `SUPABASE_WORKER_PASSWORD` | Secret | Worker token acquisition | Generated local-only | Vercel encrypted env | Deferred | Vercel encrypted env; Auth admin owner | 90 days, exposure, auth anomaly |
| `WORKER_MAX_SLICE_SECONDS` | Internal | Worker runtime guard | `240` default | Measured value <= provider max | Deferred | Config/env inventory | Runtime/provider change |
| `PARSER_VERSION` | Internal | Worker and persistence RPC | Build constant | Release artifact | Deferred | Source/release metadata | Parser release |

The proposed worker account must carry an admin-managed `app_metadata` claim, cannot sign into the web UI, and receives no owner table grants. If staging proves repeated Auth sign-in unsuitable for serverless invocation, stop and amend ADR 0005; do not silently substitute a service-role key.

Missing or invalid worker configuration fails before claiming a job. Browser bundles must contain none of these variables. Any deployment variable change requires a new worker deployment and staging smoke.

## Third-party integration delta

- Supabase: canonical schema, private Storage worker-read policy, Auth worker identity, job lease RPCs, quotas/egress measurement, security/performance advisors.
- Vercel or alternate worker runtime: bounded internal invocation, exact region, max duration/memory, encrypted env, logs, rollback. Runtime is not accepted until a 72 MiB synthetic benchmark passes with at least 25% time/memory headroom.
- Supabase Queues/pgmq is optional, not assumed. Existing `import_jobs` remains authoritative until an adoption ADR proves migration, visibility timeout, RLS, and local/staging parity.
- Supabase Edge Functions are not the default parser runtime because the current hosted limit is 256 MiB, 150 seconds on Free, and 2 seconds CPU per request; they may be used only as a narrowly scoped broker after a separate spike.
- Stable staging uses synthetic data only. Record plan, region, storage/egress usage, account owner, recovery contact, and offboarding steps in the integration register.

## Security and privacy review

- [ ] Worker authentication and authorization accepted in ADR 0005.
- [ ] Worker cannot use browser routes or access objects without an active lease.
- [ ] Owner and cross-owner claim/read/write/delete tests pass.
- [ ] Canonical tables have RLS and explicit least-privilege grants.
- [ ] Worker persistence uses fixed-signature RPCs with explicit worker, owner, import, and lease checks.
- [ ] Function execute is revoked from `PUBLIC`/`anon`; definer helpers use empty search paths and are advisor-reviewed.
- [ ] Size, nesting depth, token length, row count, batch byte size, attempts, and runtime are bounded.
- [ ] Raw ECG/RRI, GPS, agreements, purchases, rankings, and unknown payloads are dropped before persistence.
- [ ] Logs/evidence prohibit values, payload excerpts, paths/names, emails, tokens, signed URLs, and credentials.
- [ ] Import/data/account deletion includes canonical rows, checkpoints, jobs, errors, and source objects.
- [ ] Replay, duplicate delivery, lease theft, stale checkpoint, and cancellation races are tested.
- [ ] Non-clinical wording remains intact; parser output is data normalization, not interpretation.

Threats and controls:

- Lease theft/cross-user processing: worker claim plus lease-generation checks in every mutation and Storage helper.
- Parser bomb: maximum depth/token/object/array/file/record counts and cancellation at each token/batch.
- Malformed-repair expansion: repair only named map fields and decimal-key lexical pattern; reparse as strict JSON.
- Credential blast radius: dedicated worker identity and RLS/RPC scope; broad service/secret key is a stop condition unless separately approved.
- Orphaned raw data: successful/cancelled imports feed the convergent cleanup path; active lease blocks cleanup until expiry/revocation.

## Work packages

| ID | Deliverable | Dependencies | Verification | Status |
| --- | --- | --- | --- | --- |
| 4A | Pure parser interfaces, registry, bounded reader/token limits, generated fixture builders | Step 3 contract | Unit tests, fuzz seeds, memory baseline | Planned |
| 4B | Approve source/metric/exclusion/timezone/unit matrix | Sanitized observations | Product/privacy review of companion matrix | Planned |
| 4C | Canonical schema, provenance, checkpoint tables, indexes, grants, RLS | 4B | Clean reset, lint, pgTAP, advisor review | Planned |
| 4D | Health/sample/sleep/activity/workout/ECG-summary streaming mappings | 4A-4C | Deterministic snapshots and mapping tests | Planned |
| 4E | Narrow motion-map tokenizer repair and strict revalidation | 4A, 4B | Valid/invalid/truncated/adversarial fixtures | Planned |
| 4F | Worker identity, claim/lease/renew/checkpoint/persist/finish RPCs and Storage read | ADR 0005, 4C | Cross-owner, stale lease, replay, credential tests | Blocked on decision |
| 4G | Retry/dead-letter/cancel/raw-part retention coordination | 4D-4F | Crash/restart, batch rollback, deletion races | Planned |
| 4H | Runtime trigger and 72 MiB performance/egress benchmark | 4F, staging | Time/memory/egress report; provider failure drill | Planned |
| 4I | Owner-visible progress/warnings and safe operational diagnostics | 4D-4G | API/browser accessibility and redaction tests | Planned |
| 4J | Staging synthetic full job, cleanup, rollback, and user acceptance | 4A-4I | Release-candidate evidence and matrix approval | Planned |

Suggested PR sequence: 4A+fixtures; 4B+4C schema; 4D mappings; 4E repair; 4F worker boundary; 4G recovery; 4H+4I runtime/UX; 4J evidence. Each merge leaves the worker trigger disabled until 4F security and 4H capacity gates pass.

## Test plan

| Layer/scenario | Fixture/data | Command/procedure | Expected result | Evidence |
| --- | --- | --- | --- | --- |
| Parser unit | Generated record per mapping, boundary values | `go test ./...` | Typed canonical records and stable safe errors | CI |
| Determinism/dedupe | Reordered/duplicated overlapping batches | Snapshot test twice and retry | Identical snapshot; no double count | CI artifact without values |
| Motion repair | Approved decimal maps plus out-of-scope syntax | Tokenizer and strict decoder tests | Only approved keys repaired | CI |
| Fuzz/limits | Deep nesting, huge token, truncated JSON, cancellation | Go fuzz corpus + bounded test | Bounded failure, no panic/OOM | CI |
| Migration/RLS | Two users plus worker/no-worker claims | Reset/lint/pgTAP/advisors | Owner reads, worker lease scope, all other access denied | Local/staging |
| Lease/retry | Crash at every batch boundary, stale generation | Integration test with fake clock | Exact resume; stale worker cannot commit | CI/local |
| Storage | Tampered/missing/reordered 20 MiB parts | Local Storage integration | Validation fails before canonical write | Local/staging |
| Performance | Generated 72 MiB file and 330 MiB multi-file export | Benchmark with RSS/time/egress capture | <256 MiB RSS, slice headroom, linear behavior | Staging record |
| Browser/API | Processing, warning, failed, cancelled states | Accessible desktop/mobile walkthrough | Safe progress; no payload/value exposure | Staging screenshot/redacted notes |
| Deletion | Active lease, completed import, repeated delete | End-to-end synthetic flow | Lease stops, canonical/source data converge to deleted | Local/staging |

## Observability and support

- Safe identifiers: request ID, import ID, job ID, file ID, parser version, lease generation hash, batch number.
- Safe fields: source-family enum, state, counts, byte counts, durations, retry count, stable error code, runtime version.
- Prohibited: metric values, timestamps when linkable to a user unless required and protected, raw/source path, filename, payload/token excerpt, email, user JWT, worker credential, signed URL, GPS/ECG content.
- Metrics: queue age, claim rate, lease loss, job duration, bytes/sec, rows/sec, warnings/errors by safe code, retries, cleanup lag, provider 401/403/429/5xx.
- Initial alert proposals: oldest queued job >15 minutes, lease loss >5% in 30 minutes, non-retryable failures >2 in one release, cleanup lag >48 hours, any cross-owner/security test failure.
- User guidance distinguishes retryable provider outage, unsupported export, malformed file, cancellation, and support escalation without asking users to send private exports.

## Rollout and rollback

- Feature gates: worker trigger disabled by default; parser version allowlist; web processing UI can remain read-only.
- Deployment order: expand schema -> parser artifact -> worker identity/policies -> disabled worker deployment -> synthetic claim -> enable one-job trigger -> staging soak.
- Staging observation: at least one uninterrupted, one crash/resume, one cancellation/deletion, and one duplicate import; 24-hour queue/cleanup observation unless explicitly shortened with reason.
- Rollback: disable trigger first, revoke worker session/secret if compromised, roll worker/API artifact back, leave expand-only schema, requeue only after checkpoint compatibility review.
- Stop conditions: any cross-owner access, raw payload/value in logs or DB, unbounded memory, parser repair outside allowlist, duplicate canonical rows, stale worker commit, source deletion under active lease, or runtime headroom below 25%.

## Evidence and handoff

Required before Step 4 completion:

- Accepted coverage/exclusion matrix and ADR 0005.
- Migration list, schema diff, clean reset/lint/pgTAP/advisors.
- Unit/fuzz/snapshot commands and counts.
- Generated fixture manifest and generator version, never real export content.
- Time/RSS/egress benchmark for 72 MiB and 330 MiB synthetic shapes.
- Staging job IDs/states and redacted provider evidence.
- Deletion/rollback drill and known-good artifact.
- Exact user approval for metrics, exclusions, warnings, ECG/GPS treatment.

## Change history

| Date | Proposed delta | Impact | Decision/approver |
| --- | --- | --- | --- |
| 2026-07-17 | Initial detailed Step 4 plan, work packages, limits, environment/secret inventory, test matrix, and rollout gates | Makes worker/provider/security and parser/data choices explicit before implementation | Proposed |
