# Implementation steps and verification gates

This roadmap turns the product architecture into executable milestones. It defines outcomes, dependencies, work streams, environment/integration impact, evidence, and user gates. Current status and scope changes live in [`DELIVERY_TRACKER.md`](DELIVERY_TRACKER.md); the SDLC is defined in [`ENGINEERING_WORKFLOW.md`](ENGINEERING_WORKFLOW.md).

## Completion language

Use these terms precisely:

- `implemented`: source code/configuration exists on a branch.
- `verified local`: required local flows and tests pass.
- `accepted`: the user verification gate passes.
- `in review`: pull request checks/review are active or merge is pending.
- `done`: accepted, merged, required provider/environment configuration verified, documentation/evidence current, and no required work remains.
- `released`: promoted to the named environment and smoke-tested under a release record.

A green build alone does not prove Auth, RLS, Storage, a provider console, hosted environment, migration, or release works.

## Rules for every milestone

### Entry gate

- Previous required milestone dependencies are `done` or an explicit compatibility/defer plan is accepted.
- A change plan based on [`templates/CHANGE_PLAN.md`](templates/CHANGE_PLAN.md) passes Definition of Ready.
- Product behavior, non-goals, acceptance scenarios, contracts, and open decisions are visible.
- Environment, secret, integration, migration, data lifecycle, test, rollout, and rollback impacts are identified.

### Required work streams

Every milestone evaluates all streams, even when the answer is “no change”:

1. product/UX and accessibility;
2. web application and API contract;
3. Go domain/use case/repository boundaries;
4. Postgres schema, grants, RLS, Storage, and migrations;
5. Auth/security/privacy/retention/deletion;
6. third-party provider and environment configuration;
7. tests, fixtures, CI, diagnostics, and support documentation;
8. rollout, failure containment, rollback/forward repair, and cleanup.

### Exit gate

- Acceptance scenarios, failure paths, and cross-user denial pass.
- Local and required hosted/staging tests use generated or reviewed sanitized fixtures.
- Provider-side setup is verified when the milestone depends on it.
- `.env.example`, environment inventory, integration register, migrations, runbooks, and user docs are updated.
- Logs and evidence contain no secret, JWT, email, health value, GPS, ECG waveform, or raw source payload.
- Pull request checks are green and review is resolved.
- The user accepts the milestone demonstration.
- The delivery tracker records evidence, residual risks, deviations, decisions, and next gate.

## Roadmap overview

| Step | Outcome | Environment gate | Important external dependency |
| --- | --- | --- | --- |
| 0 | Repository/developer baseline | Local + CI baseline | GitHub, Node, Go, Docker, Supabase CLI |
| 1 | Next.js/Go vertical slice | Local + CI | GitHub Actions |
| 2 | Auth, profile, SSR session, JWT, RLS | Local; hosted design recorded | Supabase, Google OAuth, Mailpit |
| 3 | Manifest and resumable private upload | Local + hosted staging | Supabase Storage, Vercel preview/staging decision |
| 4 | Huawei JSON parsing and normalization | Local + staging jobs | Supabase Postgres/Storage |
| 5 | Legacy XLS backfill | Local + staging jobs | Pinned XLS library |
| 6 | Summary, goals, dashboard, reports | Local + staging UX | Vercel staging, Supabase staging |
| 7 | Scores, trends, deterministic suggestions | Local + staging UX | No AI/medical provider |
| 8 | Security, deletion, CI, diagnostics, operations | Full staging readiness | GitHub protection/scans, monitoring decision, cron/jobs |
| 9 | Production integrations and controlled launch | Production release | Vercel, Supabase, Google, SMTP, DNS, monitoring |

## Step 0 - Repository and developer baseline

Status: `done` on `main`.

Outcome: a new contributor can identify prerequisites, run the source tree, and avoid committing secrets or personal exports.

Required deliverables:

- monorepo folders, `.gitignore`, application-level environment examples, editor conventions, and root README;
- supported Node/npm and Go versions plus Docker/Supabase CLI prerequisites;
- GitHub remote/default branch and CI skeleton;
- no Huawei export, credential, generated environment file, or raw health fixture in Git;
- documentation map and ownership established.

Baseline verification:

```text
git status --short
node --version
npm --version
go version
npx supabase --version
```

Exit evidence: repository layout and local commands are established. Future onboarding gaps update this step's documentation without reopening completed code unless the baseline no longer works.

## Step 1 - Local web/API vertical slice

Status: `done` on `main` through PR #1.

Outcome: the browser calls a versioned Go health endpoint through explicit configuration and renders a usable application shell.

Required deliverables:

- Next.js App Router shell with responsive styling and accessible states;
- Go HTTP boundary with health endpoint, request ID, JSON response/error shape, and clean-architecture package direction;
- initial API contract/typed client boundary;
- environment example for the browser-visible API URL;
- web lint/typecheck/build, enforced Go formatting/vet/tests, and documentation checks in CI.

Baseline verification:

```text
cd apps/web
npm run lint
npm run typecheck
npm run build

cd ../../services/api
gofmt -l .
go vet ./...
go test ./...
```

Exit evidence: landing page and API status work locally and baseline checks are required on pull requests.

## Step 2 - Supabase Auth, profiles, JWT verification, and RLS

Status: `accepted`, PR #2 is green and awaiting merge. It becomes `done` after merge and tracker update.

Outcome: a user can register and confirm email locally, sign in with email/password or Google, keep an SSR cookie session, read only the user's profile, call a JWT-protected API boundary, and sign out.

Delivered work streams:

- profile migration, owner-only RLS policies, explicit Data API grants, timestamp trigger, and auth-user profile trigger;
- Supabase SSR client/cookie handling, email/password actions, Google PKCE initiation/callback, account state, and sign-out;
- Go RS256/JWKS verifier, bearer middleware, and authenticated user context;
- build-safe missing-environment behavior for generic CI;
- local Mailpit and Google OAuth setup documentation using `npx supabase` and the publishable key name.

Required verification:

Start `npm run dev` in another terminal before the E2E command.

```text
npx supabase --help
npx supabase db reset

cd apps/web
npm run lint
npm run typecheck
npm run build
npm run test:e2e

cd ../../services/api
gofmt -l .
go test ./...
```

Manual/local scenarios:

- email sign-up creates a pending account, Mailpit captures the confirmation, and confirmed credentials sign in;
- invalid/unconfirmed credentials show a safe error;
- Google provider completes the exact Google -> Supabase -> Next.js callback chain;
- account page shows the signed-in profile and sign-out removes access;
- missing, malformed, expired, wrong-issuer, and wrong-audience API tokens are rejected;
- User A cannot select/update User B's profile through the Data API or application path.

Environment/integration result:

- Mailpit is the expected local mailbox; it does not deliver to a real inbox.
- The local Google client secret lives only in the shell that starts Supabase.
- Hosted Supabase projects, hosted Google clients, custom SMTP, Vercel variables, and production domains remain planned work; they are not implied by local acceptance.

User gate: accepted on 2026-07-15. Remaining gate is merge of the green pull request.

## Step 3 - Import manifest and resumable private upload

Outcome: a user can select a Huawei export folder or ZIP, review a privacy-preserving manifest, upload logical files directly to private Storage in bounded resumable parts, recover from interruption, and create exactly one user-owned import job without proxying file bodies through Vercel.

### Entry gate

- Step 2 is merged and recorded `done`.
- Step 3 change plan and import state/contract are accepted.
- Decide shared staging Supabase versus Supabase Branching before hosted verification.
- Confirm current Supabase Storage, Vercel request/body, browser memory, project quota, and file-size assumptions from official sources.
- Define generated fixtures, including a logical file larger than the part size; never use the personal export in CI or screenshots.

### Work packages

1. Contract and state model
   - versioned manifest schema, source-family classification, stable file/part IDs, SHA-256, size, part count, and client capability metadata;
   - import/file/part/job state machines, idempotency keys, stable error codes, retryability, cancellation, and terminal states;
   - OpenAPI request/response limits and no file bytes on Go/Vercel completion endpoints.
2. Database and RLS
   - `import_runs`, `import_files`, `import_file_parts`, `import_jobs`, and `import_errors` with owner IDs, timestamps, provenance, parser version, retry count, and cleanup deadlines;
   - explicit grants, owner-only RLS, useful indexes/constraints, idempotency uniqueness, and safe state-transition writes;
   - positive owner and negative cross-user tests.
3. Private Storage
   - private bucket and `imports/{user_id}/{import_id}/{file_id}/part-{index}` path validation;
   - policies for create, read, update/upsert if used, and delete tested independently;
   - signed/direct upload design, checksum/size verification, and no public object URL.
4. Browser scanner
   - Web Worker folder/ZIP enumeration, supported/excluded classification, streaming/incremental hashing where practical, exact-file duplicate detection, cancellation, and manifest review;
   - do not read all large files into one JavaScript buffer and never log names/content that can expose private source data.
5. Upload/recovery
   - 20 MiB logical Storage-object maximum unless current provider constraints require a lower accepted value; use Supabase's currently required 6 MiB TUS transport chunks and recheck before implementation;
   - bounded concurrency of three, retry with jitter/backoff, pause/resume/cancel, persisted non-secret progress, checksum mismatch handling, and safe browser refresh recovery;
   - explicit completed-part reconciliation rather than trusting client state alone.
6. Go completion/job boundary
   - authenticated manifest/completion endpoints, owner scoping, validation, idempotent job creation, partial/duplicate/tampered request handling, and redacted structured logs;
   - verify declared part count/size/checksum metadata before a job becomes runnable.
7. Import wizard
   - instructions, source selection, manifest review, duplicate/exclusion summary, progress, offline/interrupted, retry, cancel, completion, warning, cleanup, and accessible/mobile states.
8. Cleanup and deletion
   - idempotent import cancellation/deletion and cleanup of failed/abandoned parts after the accepted retention period;
   - job/cleanup retries cannot delete another user's objects or a newer successful upload.
9. Hosted staging integration
   - configure dedicated non-production Supabase Storage/Auth/database and Vercel preview/staging variables;
   - run a synthetic browser-to-Storage-to-Go-job flow, quota/limit checks, and outage/recovery test;
   - record provider-side evidence and failure behavior without values or raw source content.

Detailed package status lives in [`DELIVERY_TRACKER.md`](DELIVERY_TRACKER.md).

### Required verification

The step adds named unit/integration/E2E scripts before claiming completion. The gate includes:

- clean Supabase reset/lint and database/Storage owner plus cross-user denial tests;
- web lint/typecheck/build and scanner/uploader unit tests;
- Go tests for contract validation, ownership, idempotency, and state transitions;
- generated multi-part fixture with assertions that no request exceeds the accepted size;
- network interruption, browser refresh, pause/resume, duplicate submit, checksum mismatch, cancel, and cleanup;
- hosted staging smoke with synthetic data and redacted diagnostics.

### Exit and rollback

- One synthetic import reaches exactly one queued job and exposes accurate progress.
- Direct Storage upload is proven; Vercel/Go never receives source file bodies.
- Cross-user row/path access and path tampering are denied.
- Failed/abandoned data is cleaned up and user deletion is idempotent.
- Rollback can disable import initiation and restore web/API deployments while expand-only schema remains for forward cleanup.

User gate: test the full wizard with a synthetic export and approve copy, progress, warning, retry/cancel, exclusions, and privacy behavior.

## Step 4 - Huawei JSON parser and canonical normalization

Outcome: queued import files stream into stable, owner-scoped normalized records with provenance, deterministic dedupe, actionable warnings, and no retained raw payload.

### Entry gate

- Step 3 job, Storage read, retry, and cleanup boundaries are done.
- Metric mapping and excluded-data matrix are reviewed.
- Sanitized/generated fixtures cover each source family and malformed motion cases.

### Work packages

- parser registry and streaming decoder for health detail, sample sequence, sport-per-minute, and motion-path files;
- canonical units/timestamps/timezone/device/source/provenance model and migration;
- sleep, activity, steps, calories, distance, duration, floors, intensity, heart rate, resting heart rate, HRV, stress, skin temperature, available SpO2, workout, and ECG-session-summary mappings;
- exact-file and record-level dedupe with deterministic natural/source keys and payload hash where needed;
- narrowly scoped tokenizer repair for decimal keys only in approved motion map fields, followed by standard JSON validation;
- batch persistence with transaction boundaries, retry-safe checkpoints, parser version, warnings/errors, and per-file/job diagnostics;
- explicit exclusion of raw ECG waveform/RRI, default GPS routes, agreement/service/purchase/ranking data, and unrelated/empty files;
- safe worker retry/dead-letter behavior and cleanup after accepted retention.

Environment/integration impact:

- no new external provider is expected; Supabase staging jobs and Storage quotas must be measured;
- parser/library upgrades are pinned and reviewed against the Supabase changelog and Go dependency/security checks;
- logs include identifiers/counts/durations, never metric values, paths containing private names, or payload excerpts.

Verification includes parser/dedupe/motion/unit tests, deterministic snapshots, malformed/truncated/oversized input, cancellation/retry, batch boundary failures, cross-user job denial, memory/throughput measurement, and a staging synthetic job.

Exit: fixtures produce stable normalized rows and provenance; duplicate data does not double count; malformed data is repaired only by the approved rule or rejected clearly; retry resumes safely; raw payload is not persisted.

User gate: approve the source-to-metric coverage matrix, exclusions, warnings, and treatment of ECG/GPS data.

## Step 5 - Legacy XLS allowlisted backfill

Outcome: selected legacy `.xls` reports fill missing historical days without overriding granular JSON or importing unrelated Huawei service data.

### Entry gate

- Step 4 canonical model and provenance/precedence rules are stable.
- An XLS reader spike confirms maintained dependency, license, supported BIFF format, memory behavior, and malformed-file safety.
- Sanitized/generated workbook fixtures are accepted; the personal workbook remains out of Git.

### Work packages

- pinned XLS adapter behind a domain interface and parser limits;
- exact sheet-name allowlist for approved daily health/sport/trend reports;
- header/type/date/unit normalization with clear ambiguous/unsupported warnings;
- precedence query: granular JSON wins; XLS inserts only missing approved periods/fields;
- deterministic dedupe, provenance, parser version, retry/checkpoint behavior, and exclusion tests for membership, purchase, card, ranking, agreement, and unrelated sheets;
- data-quality report comparing covered dates and conflicts without exposing health values in logs/evidence.

Verification includes approved/excluded/unknown sheet fixtures, malformed cells/workbooks, duplicate import, precedence conflict, timezone/date boundaries, memory limits, cancellation/retry, and staging job execution.

Exit: approved sheets backfill only missing history, provenance and warnings are visible, excluded sheets never persist, and a dependency/offboarding path is documented.

User gate: review historical coverage, conflict counts, excluded sheets, and ambiguous fields.

## Step 6 - First summary, goals, dashboard, and reports

Outcome: after import, a user can understand coverage/quality, confirm timezone, set wellness goals, and inspect responsive 7/28/90-day summaries without medical claims.

### Entry gate

- Steps 4-5 expose stable normalized/query contracts and realistic seeded synthetic data.
- UX information architecture and mobile priority are approved.
- Aggregation/timezone definitions and empty/missing-data semantics are documented.

### Work packages

- daily summary/query migrations and API contracts with owner scoping and bounded date windows;
- first-import summary: range, metric coverage, device/source, timezone, warnings, provenance, and reprocessing status;
- goal CRUD for steps, active minutes, workouts, sleep duration, and bedtime consistency with validation/history semantics;
- dashboard and reports with loading/empty/partial/error/unauthorized states, accessible charts/tables, responsive hierarchy, and safe units;
- cache/revalidation strategy that cannot cross users;
- deterministic synthetic seed and browser E2E for import -> summary -> goals -> dashboard;
- performance budgets and redacted query diagnostics.

Environment/integration impact: deploy to stable staging using synthetic data; no new production provider or secret should be required. New variables or analytics tools require separate review.

Exit: seeded user completes the full flow without database edits; timezone and missing coverage are explicit; queries are user-scoped and performant; UI is accessible/mobile-ready.

User gate: approve hierarchy, terminology, goals, date windows, partial-data behavior, and first visual direction.

## Step 7 - Explainable scores, trends, suggestions, and safety copy

Outcome: deterministic wellness scoring and goal trends are transparent, coverage-aware, testable, and explicitly non-clinical.

### Entry gate

- Step 6 data/query definitions are stable.
- Score inputs, thresholds, weights, missing-data behavior, forecast scope, and wording are accepted.
- No external AI/medical inference provider is in scope.

### Work packages

- versioned score domain model: sleep 30%, activity 30%, recovery/cardio 25%, goal consistency 15%; missing components reweight with visible coverage;
- immutable score snapshots/provenance and deterministic recomputation/versioning;
- 28-day goal-completion trend only, with minimum-data and uncertainty/coverage rules;
- rule-based suggestions that cite data window and evidence without diagnosis, treatment, ECG interpretation, or medical outcome prediction;
- boundary, missing-data, timezone, backfill/recompute, and wording tests;
- reports UI and explanation/detail states, including “insufficient data.”

Environment/integration impact: no new third-party inference service, secret, or health-data egress. Adding one later requires a new product/privacy/architecture decision.

Exit: fixed fixtures always produce expected results; version/provenance is visible; missing data cannot masquerade as a low score; copy stays within the non-clinical boundary.

User gate: approve weights, labels, thresholds, missing-data behavior, forecast wording, and suggestion tone.

## Step 8 - Security, deletion, CI, diagnostics, and operational readiness

Outcome: the complete staging system is supportable, privacy-safe, recoverable, and blocked from production until every required automated and operational control is green.

### Entry gate

- Product flows from Steps 2-7 are functionally accepted.
- Threat model/data-flow inventory and production readiness change plan are reviewed.
- Monitoring, deployment topology, quota/plan, CAPTCHA/abuse, and job scheduler decisions are made or have accepted controls.

### Work packages

1. Data lifecycle and deletion
   - import cancel/delete, health-data delete, account delete, Storage cleanup, job cancellation, retention deadlines, confirmation/re-auth, idempotency, audit evidence, and failure reconciliation.
2. Security hardening
   - cross-user authorization suite, RLS/Storage grants/policies, JWT/session expiry, CSRF/origin/redirect controls, rate/size limits, abuse/CAPTCHA decision, dependency/vulnerability/secret scanning, headers, and provider-account MFA/access review.
3. CI and quality gates
   - locked installs; web lint/typecheck/build/unit/E2E; Go format/vet/test; OpenAPI compatibility; migration reset/lint/RLS/Storage tests; parser fixtures; dependency/license/vulnerability and secret scans; required unique GitHub checks and protected `main`.
4. Jobs and resilience
   - retry-safe import worker/cron, lease/timeout/dead-letter/reconciliation, bounded concurrency, duplicate delivery, graceful degradation, and load/soak tests.
5. Diagnostics and support
   - structured redacted logs, release/request/import/file/job IDs, safe metrics/traces/uptime, alert routing, runbooks, support diagnostics, and synthetic failure tests.
6. Readiness reviews
   - performance/capacity/quota/cost, backup/restore posture, provider status/failure, privacy wording, accessibility, browser/device compatibility, incident/hotfix exercise, and release rollback rehearsal in staging.

Environment/integration impact:

- create protected GitHub staging/production environments where supported;
- configure monitoring with strict field allowlists and no raw health/identity data;
- configure protected job/cron credentials and endpoints if adopted;
- verify staging Supabase/Vercel plans, quotas, access ownership, and recovery contacts;
- update every integration record and secret review date.

Exit: all required CI checks are active and green, deletion is proven end to end, staging diagnostics/alerts catch a synthetic failure without sensitive content, incident/rollback rehearsal succeeds, and the production-readiness checklist has no unaccepted critical gap.

User gate: approve deletion semantics, monitoring/redaction, support/incident process, plan/cost assumptions, and readiness to provision production.

## Step 9 - Production integrations, release automation, and launch

Outcome: an isolated production system is provisioned, configured, migrated, deployed, smoke-tested, monitored, and recoverable through an approved release record.

### Entry gate

- Step 8 is `done` and production release is explicitly authorized.
- Production domains/DNS, Vercel projects, Supabase project/plan, Google client, SMTP provider/domain, and monitoring are selected with owners and recovery access.
- Provider accounts use MFA; billing/quota/budget alerts and support paths are understood.
- [`RELEASE_RUNBOOK.md`](RELEASE_RUNBOOK.md) has been rehearsed in staging.

### Work packages

1. Provision production Supabase with region/plan, Auth, Postgres, private Storage, SSL/network/security settings, backups/PITR decision, access ownership, and no copied staging data.
2. Provision production Google OAuth client/consent configuration with exact HTTPS origin and hosted Supabase callback; keep scopes limited to sign-in.
3. Provision transactional Auth SMTP with dedicated sender/domain, SPF/DKIM/DMARC, disabled link tracking, templates, rate limits, deliverability/bounce tests, and rotation/offboarding plan.
4. Provision Vercel web/API production projects/domains and environment-scoped variables; mark secrets Sensitive; verify builds and runtime identity from the exact candidate SHA.
5. Configure DNS/TLS and optional Supabase/Auth custom domain with rollback to platform domains.
6. Configure protected migration and deployment automation: stage builds, apply/verify migration, promote API/web, smoke, monitor, and record deployment IDs.
7. Configure production diagnostics/alerts, job scheduling, retention/cleanup, quota/budget alerts, incident contacts, and provider audit access.
8. Execute the first release record with a dedicated test account and synthetic data; prove app rollback and database forward-repair/recovery posture.
9. Complete final privacy/safety/security/access review and remove stale local/test callbacks or credentials from production providers.

### Production acceptance

- Preview/staging cannot access production data or credentials.
- Exact email/password and Google Auth flows work over HTTPS; reset and sign-out are verified.
- API JWT validation, owner isolation, RLS, Storage policies, import, cleanup, and deletion pass production smoke with synthetic data.
- Production migration history matches the repository and the application identifies the released SHA.
- Alerts/logs are useful and redacted; provider quotas and billing controls are visible.
- Vercel rollback target and migration compatibility are recorded; restore/forward-repair decision is understood.
- No production user data is accepted before all critical gates and explicit launch approval pass.

User gate: approve the completed release record and production launch. After launch, record observation results, incidents, and follow-up work in the delivery tracker.

## Handoff format

At every milestone or significant work-package handoff, report:

1. step/work package and precise status;
2. outcome demonstrated and acceptance scenarios;
3. files, contracts, migrations, provider-console actions, environments, and integrations changed;
4. configuration/secret names and stores changed, never values;
5. commands, CI/staging evidence, and manual flow results;
6. security, privacy, retention, deletion, and logging impact;
7. rollout, rollback/forward repair, cleanup, and known-good target;
8. risks, open decisions, deviations, deferred work, and owners;
9. exact user approval or external action needed next.
