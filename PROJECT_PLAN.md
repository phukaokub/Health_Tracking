# Personal Health Tracking Web Application

## Project status

Implementation is active. The repository/developer baseline and local web/API slice are merged; Supabase Auth and profile/RLS work has passed user verification and its merge state is tracked in [`docs/DELIVERY_TRACKER.md`](docs/DELIVERY_TRACKER.md). No Huawei health data is committed to Git; only sanitized schema observations are included below.

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
docs/                     SDLC, environments, integrations, decisions, runbooks
.github/workflows/        CI, preview, production, and maintenance workflows
```

Frontend layers are presentation, application/use cases, domain, and infrastructure/API client. Backend layers are HTTP adapters, application services, domain services, and Postgres/Storage adapters. The OpenAPI document is the contract for `/api/v1` and generates the typed frontend client.

Deploy two Vercel projects from this repository: a Next.js web project and a Go API project. Use a future apex/`www` domain for the web project and `api.<domain>` for the API. Supabase provides Auth, Postgres, and private Storage.

## Planning and delivery governance

- This file is the stable product and architecture baseline.
- [`docs/IMPLEMENTATION_STEPS.md`](docs/IMPLEMENTATION_STEPS.md) defines milestone outcomes, dependencies, environment gates, and acceptance evidence.
- [`docs/DELIVERY_TRACKER.md`](docs/DELIVERY_TRACKER.md) owns current status, active work packages, risks, decisions, and changes to the baseline.
- [`docs/ENGINEERING_WORKFLOW.md`](docs/ENGINEERING_WORKFLOW.md) defines Definition of Ready/Done, branch/PR workflow, verification, change control, and incident/hotfix paths.
- Every non-trivial work package uses a change plan. Expensive-to-reverse architecture decisions use an ADR. Every production release uses a release record.
- “Implemented,” “verified local,” “accepted,” “done,” and “released” are distinct states. No milestone is complete based only on source code or a green build.

## Environment and integration architecture

- Environments are local, CI, pull-request preview, stable staging, and production. Preview/staging use only synthetic data and a non-production Supabase project or isolated preview branch.
- Production uses separate Supabase, Vercel, Google OAuth, SMTP, domain, monitoring, and deployment configuration. Preview must never point to production data or credentials.
- Public browser configuration uses `NEXT_PUBLIC_*` variables and Supabase publishable keys. Provider secrets, Supabase secret/service credentials, deployment tokens, and SMTP credentials remain in approved server/provider stores.
- External services are not considered integrated until provider-side configuration, callback/origin settings, failure behavior, quota/cost, ownership, rotation, and staging evidence are recorded in [`docs/THIRD_PARTY_INTEGRATIONS.md`](docs/THIRD_PARTY_INTEGRATIONS.md).
- Production provisioning and promotion follow [`docs/ENVIRONMENTS_AND_SECRETS.md`](docs/ENVIRONMENTS_AND_SECRETS.md) and [`docs/RELEASE_RUNBOOK.md`](docs/RELEASE_RUNBOOK.md).

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
3. Files larger than 20 MiB are split with `Blob.slice()` into logical objects no larger than 20 MiB. The largest current file therefore becomes four Storage objects.
4. Logical objects upload directly to private Supabase Storage using resumable TUS uploads, with pause/resume, retries, per-part checksums, and maximum concurrency of three. Supabase's current TUS guidance requires 6 MiB transport chunks, so a 20 MiB logical object uses multiple network requests.
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

- The current pull-request workflow provides documentation link/credential-pattern checks, locked Node install, web lint/typecheck/build, and enforced Go formatting/vet/tests. Additional gates must not be described as active until implemented.
- Step 8 expands required checks to vulnerability/dependency/license and repository-wide secret scans, Supabase migration/RLS/Storage tests, OpenAPI compatibility, parser fixtures, and Playwright critical-path tests.
- Preview deployments use a separate Supabase staging project or isolated preview branch and seeded synthetic data only; never production health data.
- Production uses protected `main`, protected environment credentials, backward-compatible Supabase migrations, staged web/API deployments from one commit, smoke tests, an observation window, and recorded rollback/forward-repair evidence.
- Use Supabase/Postgres-backed import jobs and a protected Vercel Cron endpoint. Each job is retry-safe and records parser version, source file, batch, duration, and failure reason.
- Structured logs must include request ID, deployment SHA, import/file/job ID, route, status, and duration. Never log health values, email addresses, coordinates, file contents, JWTs, or raw authorization headers.

## Acceptance criteria

- The supplied export can be selected as a folder or ZIP and uploaded with logical Storage objects no larger than 20 MiB, current TUS transport requests no larger than 6 MiB, and metadata-only Vercel requests comfortably below the 4.5 MiB Function payload limit.
- Duplicate files are skipped and duplicate metric records are not double-counted.
- Sleep, activity, heart-rate, HRV, stress, skin-temperature, ECG-summary, and selected legacy daily-report data produce normalized records and dashboard coverage statuses.
- Malformed motion JSON is either safely repaired according to the documented rule or rejected with an actionable error.
- Import retry, cancellation, deletion, user isolation, Storage RLS, database RLS, and account deletion are tested.
- No original Huawei export or raw health value is committed to Git, logs, telemetry, screenshots, or fixtures.
- Every runtime variable and provider credential has a classification, owner, allowed store, environment scope, and rotation trigger; secret values never appear in documentation or browser bundles.
- Email/password and Google Auth are tested separately in local and hosted staging, including exact callback URLs, failure states, and sign-out/session behavior.
- Production cannot accept user data until isolated environments, custom Auth email delivery, provider ownership/MFA, backups/recovery posture, diagnostics/alerts, deletion, release smoke tests, and rollback are approved.

## Delivery phases

0. Repository and developer baseline.
1. Local Next.js/Go vertical slice and CI baseline.
2. Supabase Auth, profiles, SSR sessions, Go JWT verification, and RLS.
3. Folder/ZIP manifest, bounded resumable private upload, import records/jobs, progress, recovery, cleanup, and hosted staging proof.
4. Streaming Huawei JSON parsers, canonical mappings, provenance, dedupe, and safe malformed-motion handling.
5. Legacy XLS allowlisted parser and historical backfill precedence.
6. First summary, timezone/coverage, goals, dashboard, and reports.
7. Explainable scores, trends, deterministic suggestions, and non-clinical safety copy.
8. Security/privacy/deletion hardening, CI expansion, diagnostics, jobs, capacity, and operational readiness.
9. Isolated production integrations, environment configuration, migration/deployment automation, release, smoke tests, monitoring, and rollback proof.

For the executable sequence and gates, see [`docs/IMPLEMENTATION_STEPS.md`](docs/IMPLEMENTATION_STEPS.md). For the current branch, decisions, risks, and next approval, see [`docs/DELIVERY_TRACKER.md`](docs/DELIVERY_TRACKER.md). The complete documentation map is [`docs/README.md`](docs/README.md).
