# Personal Health Tracking Web Application

## Project status

This is a greenfield project. The repository directory was empty when inspected. No Huawei health data is committed to Git; only sanitized schema observations are included below.

The supplied Huawei export contains approximately 330 MiB of files and approximately 170 MiB of unique non-empty JSON. The export includes duplicate health-detail batches, triplicate motion-path batches, 8 ECG session summaries, 144 detailed sleep records, 13,299 activity records, and a legacy 74-sheet `SportsHealth-Data.xls` workbook.

## Product goal

Create a private, multi-user wellness application that guides a user from Huawei Health export request through import, first summary, goal setup, reports, scoring, trend forecasting, and explainable suggestions.

V1 is wellness-oriented and non-clinical. It must not diagnose conditions, interpret ECG waveforms, predict medical outcomes, or expose raw ECG/GPS data by default.

## Technology and repository structure

```text
apps/web/                 Next.js, React, TypeScript, Tailwind, shadcn/ui
services/api/             Go HTTP API and clean-architecture domain logic
supabase/                 SQL migrations, RLS policies, local Supabase config
docs/design/              Brand and UI prompt brief
docs/                     Architecture, import mapping, runbooks
.github/workflows/        CI, preview, production, and maintenance workflows
```

Frontend layers are presentation, application/use cases, domain, and infrastructure/API client. Backend layers are HTTP adapters, application services, domain services, and Postgres/Storage adapters. The OpenAPI document is the contract for `/api/v1` and generates the typed frontend client.

Deploy two Vercel projects from this repository: a Next.js web project and a Go API project. Use a future apex/`www` domain for the web project and `api.<domain>` for the API. Supabase provides Auth, Postgres, and private Storage.

## Authentication and authorization

- Supabase Auth provides verified email/password registration, sign-in, password reset, and Google OAuth with PKCE.
- Next.js uses Supabase SSR cookies and handles OAuth callbacks.
- The browser sends Supabase access tokens to the Go API. The Go API verifies issuer, audience, expiry, and signature using Supabase JWKS.
- Every health record belongs to an authenticated Supabase user. Go repositories always filter by user ID.
- Enable RLS on application and Storage tables. Never expose service-role or database credentials to the browser.
- Include account deletion, health-data deletion, import deletion, session expiry, CSRF/origin checks, and rate limits for authentication/import endpoints.

## Import design for the supplied export

### Upload protocol

The large-file solution is browser-side part upload, not a Vercel upload proxy. Vercel Functions have a 4.5 MiB request-body limit, while the largest supplied JSON file is about 70.8 MiB.

1. User selects the Huawei export directory or a ZIP.
2. A Web Worker scans files and creates a manifest containing relative path, source family, size, SHA-256, and part count.
3. Files larger than 20 MiB are split with `Blob.slice()` into 20 MiB parts. The largest current file therefore becomes four Storage objects.
4. Parts upload directly to private Supabase Storage using resumable TUS uploads, with pause/resume, retries, per-part checksums, and maximum concurrency of three.
5. Go receives only the manifest and completion metadata, verifies part count/size/checksum, and creates one idempotent processing job per logical file.
6. The Go parser reads parts sequentially with `io.MultiReader` and streams records in database batches of 500–1,000.

Storage path:

```text
imports/{user_id}/{import_id}/{file_id}/part-{index}
```

Delete all parts after successful processing or after 24 hours for failed imports. Supabase Free supports 1 GB Storage, but its maximum individual file limit is 50 MB; the part strategy keeps the current export compatible with that limit. Upgrade to Pro later for backups, reliability, and larger object limits rather than because of this upload protocol.

### File classification and precedence

- `Health detail data & description`: primary source for heart rate, resting heart rate, sleep stages, HRV, stress, active hours, exercise intensity, skin temperature, and available oxygen data.
- `Sample sequence data & description`: import detailed sleep summaries and ECG session metadata; do not store raw waveform/RRI payloads in the first dashboard release.
- `Sport per minute merged data & description`: primary source for steps, calories, distance, duration, floors, altitude, and movement intensity.
- `Motion path detail data & description`: import workout summary fields; GPS route storage is opt-in and off by default.
- `SportsHealth data & desciption`: read selected legacy XLS sheets—daily health statistics, daily sport statistics, sport dimensions, health reports, and trend reports—to fill missing historical days only. Granular JSON always has precedence.
- Agreement-signing files, membership/purchase/card/ranking/privacy records, empty run-plan files, and empty route files are excluded.

### Huawei-specific normalization

- Deduplicate exact duplicate files by SHA-256 before upload.
- Deduplicate records with source record ID, metric key, timestamps, device/source, and payload hash; Huawei exposes some metrics under both legacy and extended type codes.
- Parse JSON with a streaming decoder; never load the complete export into memory.
- Motion JSON contains unquoted decimal map keys. Apply a narrowly scoped tokenizer repair only inside known `paceMap`, `paceMapNative`, and `partTimeMap` objects, then validate standard JSON. Reject any other malformed syntax.
- Use a tested Go legacy-XLS reader for the 74-sheet workbook. Import only approved sheet names and record parser warnings for unsupported sheets.

### Data model

Core tables: `profiles`, `import_runs`, `import_files`, `import_file_parts`, `import_jobs`, `import_errors`, `devices`, `health_samples`, `daily_health_summaries`, `sleep_sessions`, `sleep_stages`, `activities`, `workout_sessions`, `ecg_sessions`, `goals`, `score_snapshots`, and `insights`.

Store UTC timestamps, the user’s IANA timezone, units, source provenance, parser version, and import ID. Store normalized data only; raw source archives, GPS tracks, ECG waveforms, agreement data, and unrelated Huawei service data are not retained.

## User experience

Pages and states:

- Public landing page: value proposition, privacy promise, supported metrics, and Huawei export instructions.
- Authentication: email/password, email confirmation, password reset, and Google sign-in.
- Import wizard: source instructions, folder/ZIP selection, manifest preview, duplicate detection, upload progress, retry/pause, parser progress, warnings, and failures.
- First summary: imported date range, metric coverage, source/device summary, timezone confirmation, and data-quality warnings.
- Goal setup: steps, active minutes, workout frequency, sleep duration, and bedtime consistency.
- Dashboard: wellness score, goal progress, key trends, data coverage, and most important detail panel.
- Reports: selectable 7/28/90-day windows, sleep/activity/cardio sections, ECG history, and export/delete controls.
- Settings: timezone, linked identities, data retention, import history, account deletion, and privacy controls.

Score weights: sleep 30%, activity 30%, recovery/cardio 25%, goal consistency 15%. Missing components are reweighted and shown with a coverage indicator. Forecasts estimate goal completion from the prior 28 days only. Suggestions are deterministic and explain the evidence behind each recommendation.

## CI/CD and diagnostics

- Pull-request workflow: locked Node install, lint/typecheck, Go format/vet/tests, vulnerability and secret scans, Supabase migration/RLS tests, OpenAPI contract tests, parser fixtures, and Playwright critical-path tests.
- Preview deployments: separate Supabase staging project and seeded demo data only; never production health data.
- Production workflow: protected `main`, backward-compatible Supabase migrations, deploy web/API to Vercel, then run public-page/auth/API/import smoke tests.
- Use Supabase/Postgres-backed import jobs and a protected Vercel Cron endpoint. Each job is retry-safe and records parser version, source file, batch, duration, and failure reason.
- Structured logs must include request ID, deployment SHA, import/file/job ID, route, status, and duration. Never log health values, email addresses, coordinates, file contents, JWTs, or raw authorization headers.

## Acceptance criteria

- The supplied export can be selected as a folder or ZIP and uploaded without sending any request larger than 20 MiB to Storage or 4.5 MiB to Vercel Functions.
- Duplicate files are skipped and duplicate metric records are not double-counted.
- Sleep, activity, heart-rate, HRV, stress, skin-temperature, ECG-summary, and selected legacy daily-report data produce normalized records and dashboard coverage statuses.
- Malformed motion JSON is either safely repaired according to the documented rule or rejected with an actionable error.
- Import retry, cancellation, deletion, user isolation, Storage RLS, database RLS, and account deletion are tested.
- No original Huawei export or raw health value is committed to Git, logs, telemetry, screenshots, or fixtures.

## Delivery phases

1. Repository bootstrap, Supabase projects, environment templates, CI skeleton, design brief, and OpenAPI contract.
2. Supabase Auth and profile/RLS foundation.
3. Folder manifest, 20 MiB part uploader, Storage policies, import jobs, and progress UI.
4. JSON parsers and canonical metric mappings.
5. Legacy XLS selected-sheet parser and historical backfill precedence.
6. Initial summary, goals, dashboard, scores, trends, and deterministic suggestions.
7. Production hardening, deletion flows, diagnostics, smoke tests, and Vercel deployment runbook.

For the executable milestone sequence, local test gates, and user verification pauses, see [`docs/IMPLEMENTATION_STEPS.md`](docs/IMPLEMENTATION_STEPS.md). The implementation thread must complete one milestone, show its local evidence, and wait for user approval before starting the next important milestone.
