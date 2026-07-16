# Change plan: Step 3 import manifest and resumable private upload

## Metadata

- Change ID: STEP-003
- Milestone/work packages: Step 3 / 3A-3I
- Owner: repository maintainer with Codex implementation support
- Status: implementation merged in PRs #3-#9; local real-browser acceptance is green; hosted work package 3I remains
- Baseline commit: `0b3ad3df618505eab31b40663e794f915d679227` (Step 2 merge)
- Branch: `codex/step-3-browser-acceptance`
- Related records: [`../IMPLEMENTATION_STEPS.md`](../IMPLEMENTATION_STEPS.md), [`../DELIVERY_TRACKER.md`](../DELIVERY_TRACKER.md), ADR 0001, ADR 0002, ADR 0003, ADR 0004, DEC-001, DEC-002, DEC-007
- Target environments: local, CI, PR preview, staging
- Explicitly excluded environment: production
- Last updated: 2026-07-17

## Outcome

An authenticated user can select a Huawei export folder or ZIP, review what will and will not be imported, upload logical files directly to private Supabase Storage with pause/resume/retry, and create exactly one owner-scoped import job. Neither Next.js nor the Go/Vercel API receives source file bodies.

### Success measures

- A generated logical file larger than 20 MiB is represented by multiple immutable Storage objects no larger than 20 MiB each.
- Each Storage object uses Supabase TUS resumable upload with the currently required 6 MiB transport chunk size; logical part size and network chunk size are distinct limits.
- No source bytes pass through a Vercel Function; metadata request/response bodies remain comfortably below Vercel's 4.5 MB payload limit.
- Network loss, pause, browser refresh, retry, duplicate completion, checksum mismatch, cancellation, and cleanup produce deterministic states.
- User A cannot inspect, overwrite, complete, cancel, or delete User B's import rows or Storage objects.
- One accepted manifest creates at most one logical import run and one initial processing job.
- Logs/evidence contain IDs, counts, durations, states, and stable error codes, but no source content, health values, raw relative paths, email, JWT, or upload authorization URL.

### Non-goals

- Parsing or normalizing Huawei metric payloads (Step 4).
- Legacy XLS content extraction (Step 5); the file can be classified and uploaded.
- Production projects, domains, SMTP, production Google OAuth, or launch (Step 9).
- Uploading an original ZIP as the sole retained source archive.
- Public Storage objects, service-role credentials in the browser, or file-body proxy endpoints.
- Cross-device resume in V1; resume is scoped to the same browser/profile unless later accepted.

## User and failure flows

### Happy path

1. Authenticated user opens the import wizard and reads privacy/source instructions.
2. User selects a directory or ZIP. A Web Worker enumerates entries, classifies supported/excluded files, computes hashes incrementally, and reports progress/cancellation.
3. UI shows file counts, logical bytes, duplicates, exclusions, warnings, estimated Storage usage, and retention behavior.
4. User confirms. The API creates an owner-scoped import run and immutable file/part records from bounded metadata pages.
5. Browser uploads each logical part directly to the private `health-imports` bucket with the user's Supabase access token and owner/path RLS.
6. Browser reconciles completed objects with the API and submits bounded completion metadata idempotently.
7. API verifies import ownership and expected object metadata, marks the run uploaded, and creates one queued job.
8. UI displays queued status and can safely refresh/poll.

### Required failure/recovery paths

- unauthenticated/expired session before scan, during upload, or at completion;
- unsupported browser folder API with ZIP fallback;
- unreadable, empty, duplicate, unsupported, oversized-by-policy, or changing-during-scan file;
- malformed/zip-bomb-like archive limits, unsafe ZIP entry path, and password-protected archive;
- network offline, TUS timeout, expired upload URL, 409 conflict, provider 429/5xx, and retry exhaustion;
- browser tab close/refresh and local resume metadata that no longer matches server state;
- one failed part while other files/parts completed;
- completion before all expected objects exist, wrong size/path/owner, stale manifest version, duplicate completion, and client/server state conflict;
- user cancel during scan/upload/queued state and repeated delete/cleanup;
- Supabase Storage or API unavailable, quota exhausted, and Vercel metadata endpoint unavailable.

Every failure maps to a stable code, retryability flag, safe user action, and support diagnostic ID.

## Impact matrix

| Area | Change | Detail |
| --- | --- | --- |
| Next.js UI | Yes | Multi-step import wizard and progress/recovery states |
| Web Worker/client infrastructure | Yes | Directory/ZIP scan, incremental hash, slicing, TUS orchestration, local resume metadata |
| Go API/domain | Yes | Import contract, owner scope, state machine, idempotency, completion, status, cancel/delete |
| OpenAPI/client | Yes | Versioned metadata-only endpoints and generated types |
| Postgres | Yes | Import run/file/part/job/error tables, constraints, indexes, grants, RLS, retention timestamps |
| Supabase Storage | Yes | Private bucket and owner/path policies for required operations |
| Supabase Auth/JWT | Reuse | Existing user session/JWT; verify expiry/re-auth behavior during long uploads |
| Third-party packages | Yes | TUS client required; ZIP and incremental SHA libraries need review/selection |
| Environment variables | Planned delta | Go-to-Supabase foreground access and hosted project configuration; no browser secret |
| Background processing | Boundary only | Create one queued job; parser execution starts Step 4 |
| Diagnostics | Yes | Redacted import/file/part/request IDs, counts, durations, states, provider error classes |
| Privacy/deletion | Yes | Raw object retention, cancellation, import deletion, abandoned upload cleanup |

## Dependencies and blocking decisions

| ID | Decision/dependency | Owner | Needed by | Proposed default |
| --- | --- | --- | --- | --- |
| STEP2 | Merge accepted Auth/RLS pull request | Maintainer | Before branch creation | Merge green PR #2 |
| DEC-001 | Shared staging Supabase vs per-PR Branching | Release owner | 3I | Shared staging with synthetic data; serialize migrations |
| DEC-002 | Stable Vercel custom Staging vs branch Preview | Release owner | 3I | Branch-specific Preview fallback |
| DEC-007 | Go foreground/background Supabase access model | Engineering owner | 3F / Step 4 | Accepted for foreground in ADR 0002: user JWT + publishable key; decide dedicated worker credential before Step 4 |
| LIB-001 | ZIP streaming library | Engineering owner | 3D | Accepted: `fflate` 0.8.3 (MIT) powers bounded local ZIP review; direct upload remains gated |
| LIB-002 | Incremental SHA-256 library | Engineering owner | 3D | Accepted: `hash-wasm` 4.12.0 (MIT) in the Worker; avoids whole-file buffering |
| LIB-003 | TUS client | Engineering owner | 3E | Accepted in ADR 0003: `tus-js-client` 4.3.1 (MIT), pinned and lockfile-reviewed, with Supabase's documented endpoint/chunk rules |
| LIMIT-001 | Confirm hosted Supabase Storage/project quotas and configured bucket limit | Billing/release owner | 3I | Do not infer current plan limits from old notes; record dashboard/docs evidence |

### DEC-007 options to resolve

1. Foreground API forwards the user's JWT plus a Supabase publishable key to Data/Storage APIs. RLS remains authoritative and no elevated secret is needed for user-driven calls. This is the proposed Step 3 default.
2. Go connects to Postgres with a dedicated non-bypass role and establishes trusted request claims/transactions correctly. This adds a server secret and more connection/RLS complexity.
3. Go uses a Supabase secret/service credential and application user filters. This bypasses RLS and has the largest blast radius; do not adopt without a strong reason and explicit security approval.

Asynchronous Step 4 workers cannot rely on a user's short-lived browser JWT. Their least-privileged database/Storage access and owner checks need a separate decision, inventory entry, rotation, and incident procedure before parser execution.

## Proposed contracts

Final names/examples belong in OpenAPI and migration files. The plan fixes the semantics first.

### Endpoint set

- `POST /api/v1/imports`: create an import from the first bounded manifest page and return server-owned IDs/state.
- `POST /api/v1/imports/{import_id}/manifest-pages`: append an ordered, idempotent metadata page when the manifest exceeds the single-request cap.
- `POST /api/v1/imports/{import_id}/complete`: reconcile expected objects and queue exactly one job.
- `GET /api/v1/imports/{import_id}`: return owner-scoped state/progress/warnings.
- `DELETE /api/v1/imports/{import_id}`: idempotently cancel and begin metadata/object cleanup.
- `POST /api/v1/imports/cleanup`: list only the caller's eligible imports whose 24-hour deadline passed, then converge each through the same Storage-first deletion path.

All endpoints require the Step 2 bearer boundary. IDs are unguessable UUIDs, but authorization always uses the verified user ID as well.

### Manifest v1 semantics

Import-level fields:

- schema version, source kind (`directory` or `zip`), client-generated idempotency key, timezone candidate, total file/logical byte counts, and page count;
- no device/account name, email, absolute local path, file content, or health values.

Logical-file fields:

- client file ID, normalized relative path or privacy-preserving display reference, source-family classification, size, SHA-256, content kind, last-modified hint, duplicate-of reference, inclusion decision, and ordered logical part descriptors;
- path normalization rejects absolute paths, drive prefixes, `..`, control characters, and ambiguous separators before any object key is formed.

Logical-part fields:

- zero-based index, byte offset/length, SHA-256, immutable object key derived from server-owned user/import/file IDs, and upload state;
- object size is at most 20 MiB; final part may be smaller.

Manifest bodies receive an accepted byte cap below 4.5 MB. Work package 3A chooses the exact cap and page/file count from measured generated fixtures; the initial target is at most 1 MiB per request. Oversized manifests use ordered idempotent pages rather than a larger request.

### State model

Import run:

```text
draft -> scanning -> awaiting_confirmation -> uploading -> uploaded -> queued
  -> processing (Step 4) -> completed | completed_with_warnings | failed
Any non-terminal pre-processing state -> cancelling -> cancelled
Terminal/expired state -> deleting -> deleted
```

Server state is authoritative after creation. Client-local state may suggest resume but must reconcile before sending bytes or transitions.

File/part states distinguish planned, uploading, uploaded, verified, failed, skipped_duplicate, excluded, and deleted. Database constraints/application transition guards reject impossible backward or cross-import transitions.

### Idempotency

- Import creation is unique per user plus client idempotency key.
- Manifest page is unique per import plus page index/content hash.
- Logical file is unique per import plus client file ID; exact-file hash can identify duplicates without collapsing separately owned imports incorrectly.
- Logical part is unique per file plus index and immutable object path.
- Completion uses a unique import transition/job key so repeated requests return the existing result.
- Cleanup/deletion can run repeatedly and converge.

## Storage and upload design

- Bucket is private and created/configured by migration or reproducible project configuration.
- Object path is `imports/{user_id}/{import_id}/{file_id}/part-{index}`. Server-generated IDs prevent raw filenames from entering object keys.
- Browser uses the user's Supabase access token directly against Storage. It never receives a service credential.
- One logical Storage object is at most 20 MiB. Supabase's current resumable-upload guidance requires a 6 MiB TUS transport `chunkSize`; a 20 MiB object therefore uses multiple PATCH requests.
- Use the hosted direct Storage hostname for hosted large uploads; local development uses the local Storage endpoint.
- Uploads are immutable and do not use `x-upsert` by default. This avoids last-writer-wins races and unnecessary UPDATE permission.
- TUS upload URLs/fingerprints may support same-browser resume but are sensitive operational metadata: never log them or send them to analytics. The server still checks owner/import/path metadata.
- Current Supabase guidance says a resumable upload URL lasts up to 24 hours; expiration and the abandoned-upload cleanup deadline must align but remain configurable in domain policy/tests.
- Storage operations go through the Storage API. Never delete rows directly from `storage.objects` because that can orphan billable objects.

### Storage policy matrix

| Operation | Needed | Rule |
| --- | --- | --- |
| INSERT | Yes | Authenticated `sub` equals first owner path segment; bucket and expected normalized path shape match |
| SELECT | Yes | Same owner/bucket/path boundary; required for object access and upload metadata return |
| UPDATE | No by default | Add only if an accepted upsert/rewrite design needs it, with SELECT + UPDATE tests |
| DELETE | Yes | Same owner/bucket/path boundary; deletion occurs through Storage API |

Test list/read behavior separately so a user cannot enumerate another user's object names.

## Data lifecycle and migrations

### Proposed tables

- `import_runs`: owner, state, manifest version, idempotency key, counts, source kind, timezone candidate, timestamps, cleanup deadline, initial job ID.
- `import_files`: owner/import, client ID, privacy-safe source reference, family, logical size/hash, include/exclude/duplicate state, parser version target.
- `import_file_parts`: owner/file, index, offset, length/hash, object key, state, upload/verified timestamps.
- `import_jobs`: owner/import, job type/state, attempt/lease/checkpoint fields, parser version, timestamps.
- `import_errors`: owner/import/file/part/job references, stable code, retryable flag, safe detail, occurrence/timestamps; no payload excerpts.

Every exposed table receives explicit grants plus RLS. Include owner ID on hot-path tables even when derivable to make scope/indexing explicit; constraints or controlled writes prevent mismatched ownership.

### Retention

- Successful raw logical-part objects are deleted after parser completion and accepted verification; normalized data remains according to user controls.
- Failed/abandoned uploads are eligible for cleanup after 24 hours unless active retry/lease evidence says otherwise. The authenticated import page reconciles caller-owned completed objects through the API when the user returns; Supabase TUS upload URLs expire after at most 24 hours. System-wide scheduled cleanup remains coupled to the Step 4 least-privileged worker credential decision.
- Cancel/delete hides the import from active UI immediately, stops future work, and reconciles object/metadata deletion asynchronously and idempotently.
- Error/support metadata has an accepted retention period before production; raw paths/content are not retained as diagnostics.

### Migration/rollback

- Add tables, enums/checks, indexes, grants, policies, and bucket configuration with no dependency from existing Auth pages.
- Clean local reset and RLS/Storage tests must pass before staging.
- Rollback disables the import entry point and rolls back web/API code. Expand-only tables remain until a later reviewed cleanup migration.
- Never use a destructive down migration during an incident; repair states/constraints forward.

## Environment and secret delta

No new browser secret is permitted.

| Planned name/capability | Class | Consumer | Local | Preview/staging | Production | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Existing web Supabase URL/publishable key | Public | Browser/TUS | Local stack | Staging project | Not in Step 3 | Already inventoried |
| Existing web/API base URLs | Public | Browser | Local | Preview/staging | Not in Step 3 | Already inventoried |
| `SUPABASE_PUBLISHABLE_KEY` | Public identifier/internal config | Go foreground adapter with user JWT | Local publishable key | Staging publishable key | Deferred | Implemented for 3F; never substitutes for the user JWT |
| Direct Storage hostname/project ref derivation | Public/internal config | Browser uploader | Local endpoint | Hosted direct Storage hostname | Deferred | Prefer safe derivation from validated Supabase URL; avoid duplicate variable if possible |
| Worker database/Storage credential | Secret | Step 4 async worker | TBD | TBD | Deferred | Explicitly not introduced until worker access decision |

Limits such as manifest version, 20 MiB logical part size, 6 MiB TUS chunk, concurrency, and retry schedule should be shared versioned code/configuration, not casually mutable deployment secrets. If made environment-configurable, define safe min/max and include them in the inventory and tests.

Hosted variables are scoped to Vercel Preview/Staging and point only to staging Supabase. Existing deployments must be rebuilt after changes.

## Third-party integration delta

### Supabase Storage

- Data: temporary encrypted-in-transit/at-rest Huawei source parts, object metadata, owner IDs, hashes, sizes, states.
- Permissions: user JWT with narrow private bucket RLS; no browser service credential.
- Provider setup: private bucket, object-size policy, INSERT/SELECT/DELETE policies, hosted direct Storage endpoint, quota/billing review.
- Current operational constraints to verify: 6 MiB TUS chunk, 24-hour upload URL, configured global/bucket file limits, project Storage/egress quota.
- Failure: pause/retry on transient errors; fail closed on 401/403/path mismatch; show quota/config error without bypass.
- Offboarding: delete objects via Storage API, remove policies/bucket only after all imports are reconciled, revoke server credentials if any were introduced.

### Vercel preview/staging

- Carries metadata-only web/API calls. The documented Function payload maximum is 4.5 MB, so source bytes are prohibited and manifest pages are capped well below it.
- Environment configuration points to staging only. Auth-enabled preview callback/origin must be exact or intentionally allowlisted.
- Failure: upload can continue only while direct Storage Auth remains valid, but completion/status safely retries when the API returns.

### Browser packages

For each TUS/ZIP/hash package, record version, lockfile, license, maintenance/security history, browser/worker support, bundle size, cancellation/memory behavior, and replacement path. Do not add a package solely from an example without a spike and test fixture.

## Security and privacy controls

- Authenticated server endpoints and user ID from verified token only.
- Owner ID appears in every query and RLS policy; negative tests use two users.
- Server-generated IDs form Storage paths; client paths cannot choose another owner/import.
- ZIP entries undergo traversal, absolute-path, symlink/unsupported feature, expansion ratio, entry count, and total uncompressed-size checks before extraction/upload.
- Manifest and completion have body, file-count, string-length, hash-format, and state-transition limits.
- Immutable upload paths and idempotency prevent overwrite/replay races.
- TUS URL, access token, local absolute path, raw filename/path, payload, email, and health value are prohibited in logs/telemetry/evidence.
- Client resume storage contains no JWT or provider secret; logout/account switch invalidates/reconciles resume state.
- Cancellation, deletion, and cleanup are owner-scoped, convergent, and observable.
- Import copy remains non-clinical and explains temporary raw-data handling.

## Work packages and pull-request slicing

| ID | Deliverable | Depends on | Suggested merge boundary | Status |
| --- | --- | --- | --- | --- |
| 3A | OpenAPI/domain contract, state machine, limits, idempotency, decision documentation | Step 2 | Contract/tests/docs only | Complete in PR #3 and extended by PR #7 |
| 3B | Database migration, constraints/indexes/grants/RLS; repository adapter in 3F | 3A | Schema + tests, feature unused | Complete in PRs #3 and #7; 38 pgTAP checks cover invoker RPCs and cross-owner denial |
| 3C | Private bucket configuration and Storage policies/tests | 3A, 3B | Storage boundary, feature unused | Complete in PRs #3 and #7; corrected owner-path policy passed a real local TUS probe |
| 3D | Worker scanner/classifier/hash and ZIP/library spikes | 3A, LIB-001/002 | Local manifest UI behind disabled entry | Complete for review in PRs #4-#6; ZIP entry upload and browser interaction evidence remain in 3E/3G |
| 3E | TUS uploader/reconcile/pause/resume/retry | 3C, 3D, LIB-003 | Synthetic local upload behind feature gate | In progress: directory path merged in PR #8; ZIP adapter now revalidates archive metadata and streams one checksummed logical part at a time into the same 6 MiB TUS transport. Browser interruption evidence remains |
| 3F | Go create/page/complete/status/delete endpoints and idempotent job boundary | 3A-3C | API integrated, UI still gated | Complete in PR #7 with 1 MiB API cap, paged manifests, user-JWT/RLS adapter, idempotent job creation, and Storage-first delete |
| 3G | Import wizard UX/accessibility/recovery | 3D-3F | Enable locally after E2E | In progress: directory flow merged in PR #8 and ZIP uses the same gated states locally; browser accessibility/mobile/interruption walkthrough remains |
| 3H | Cancel/delete/abandoned cleanup and reconciliation | 3B, 3C, 3F | Required before hosted enablement | In progress: owner-scoped expired-run listing and Storage-first API deletion pass locally; direct table writes are revoked per ADR 0004. System-wide scheduling remains tied to the Step 4 worker credential decision |
| 3I | Staging Supabase/Vercel config and hosted synthetic E2E | DEC-001/002, 3A-3H | Milestone completion gate | Planned |

Each pull request updates this plan/tracker and contains a safe enable/disable boundary. No remote user can start imports before 3H is complete.

## Test plan

| Layer | Required fixtures/scenarios | Evidence |
| --- | --- | --- |
| Domain/API | State table, idempotent create/page/complete/delete, invalid transition, oversized metadata, stale version | Go unit/contract tests |
| Database | Clean reset, constraints, grants, owner CRUD, User A vs User B denial, duplicate keys, transition races | Supabase local tests/lint |
| Storage | INSERT/SELECT/DELETE owner path, list/read denial, tampered path, immutable conflict, no UPDATE by default | Local Storage integration tests |
| Scanner | Directory + ZIP, duplicates, empty/excluded/unsupported, path traversal, cancellation, changing file | Worker unit tests |
| Hash/slicing | Known vectors, 0/1/exact-boundary/over-boundary sizes, 70+ MiB generated file, no full-export buffer | Browser/unit memory assertions |
| TUS | 6 MiB transport chunks, 20 MiB logical object, progress, offline, timeout, retry, refresh resume, 409, expired URL | Mock/local Storage tests |
| Browser E2E | Instructions -> review -> upload -> queued, pause/reload/reselect resume, cancel/delete, mobile/keyboard/ARIA states, cross-owner denial | Green locally with generated 8 MiB ZIP in Chromium; CI gate awaits PR proof and hosted repeat remains |
| Hosted staging | Auth callback, direct Storage hostname, metadata payload cap, quota error, Storage/API outage, redacted logs | Release-candidate evidence |

Test fixtures are generated at runtime or committed only after sanitization review. CI must not need the personal export.

## Diagnostics and support

Safe structured fields: release SHA, request ID, user-scoped opaque import/file/part/job IDs, state, source-family code, counts, declared byte totals, duration, attempt, HTTP/provider status class, stable error code.

Prohibited: user ID when not needed, email, JWT/authorization header, TUS URL/signature, local path/raw filename, object content, hash tied to a real personal file in public evidence, health values, GPS, ECG, ZIP entry content.

Metrics: scan/upload duration histograms, bytes/parts by synthetic/aggregate category, retry/failure/cleanup counts, jobs stuck by state/age, provider 401/403/409/413/429/5xx rates. Production metric selection is Step 8 and must avoid low-cardinality leaks becoming user identifiers.

## Rollout, rollback, and stop conditions

Rollout order: contract -> expand schema/RLS -> Storage policies -> scanner/uploader -> API -> cleanup -> local E2E -> hosted staging -> user acceptance. Import entry remains disabled until cleanup and cross-user tests pass.

Rollback:

- disable import entry and job pickup;
- roll web/API deployments to the known-good Step 2 version;
- leave expand-only schema and private bucket in place;
- reconcile/delete synthetic orphan objects through Storage API;
- fix state/policy errors forward before re-enabling.

Stop immediately for any cross-user access, browser-visible secret, source bytes reaching Vercel/Go, unbounded archive/memory behavior, cleanup deleting an unexpected object, duplicate job creation, or sensitive value in logs/evidence.

## Definition of Ready gaps

- [x] Step 2 merged.
- [ ] DEC-001 accepted.
- [ ] DEC-002 accepted or explicitly deferred until 3I.
- [x] DEC-007 foreground access model accepted in ADR 0002.
- [x] Manifest page cap and privacy-safe path-retention/display rule implemented in 3A/3F.
- [x] TUS/ZIP/hash dependencies and limits implemented and verified locally.
- [ ] Hosted staging account/plan/quota owner identified before 3I.

## Approval requested

Approve this plan's outcome, non-goals, work-package order, proposed foreground user-JWT/RLS access model, 20 MiB logical object plus 6 MiB TUS chunk distinction, and the defaults for shared synthetic staging and branch-specific Preview. Approval moves status from `proposed` to `ready` after Step 2 merges.

## Change history

| Date | Delta | Impact | Decision |
| --- | --- | --- | --- |
| 2026-07-15 | Initial instantiated plan created from the new SDLC template | Makes environment, provider, secret, state, test, cleanup, and rollback work explicit before coding | Proposed |
| 2026-07-16 | Corrected merged PR status and accepted foreground user-JWT/RLS access | PRs #3-#6 are delivery evidence; remaining Step 3 work is tracked independently | Accepted ADR 0002 |
| 2026-07-17 | Added reproducible real-browser acceptance after PRs #3-#9 merged | Found and fixed dynamic public-env lookup; proves interrupted ZIP resume, one job, owner isolation, and cleanup with generated data | Local gate accepted; hosted 3I still required |

## Current primary references

- [Supabase resumable uploads](https://supabase.com/docs/guides/storage/uploads/resumable-uploads) for the TUS endpoint, 6 MiB chunk requirement, resume behavior, direct Storage hostname, conflicts, and upload URL lifetime.
- [Supabase Storage access control](https://supabase.com/docs/guides/storage/security/access-control) and [ownership](https://supabase.com/docs/guides/storage/security/ownership) for operation-specific RLS and `owner_id`.
- [Supabase Storage schema](https://supabase.com/docs/guides/storage/schema/design) for the requirement to delete objects through the API rather than deleting metadata rows.
- [Vercel Function limits](https://vercel.com/docs/functions/limitations) for the current 4.5 MB request/response payload ceiling.

Recheck these sources and the provider dashboards during 3A/3I; do not treat the 2026-07-15 review as permanent.
