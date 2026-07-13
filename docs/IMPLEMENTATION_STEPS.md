# Implementation Steps and Verification Gates

This file turns the architecture plan into small, reviewable milestones. Each milestone must pass its local verification gate before the next one starts. The user verification gate is an intentional pause: review the result and approve continuation in the task thread.

## Working rules

- Keep Huawei exports, raw health values, credentials, `.env` files, and Supabase service-role keys out of Git.
- Every feature must have a local test path before it is connected to Vercel or production Supabase.
- Use a separate Supabase project for preview/testing and a production project only after the local gate is green.
- Prefer thin vertical slices: UI, API, database/RLS, and tests should land together when they form one usable flow.
- At the end of each step, report changed files, commands run, test output, known limitations, and the exact user decision needed.

## Milestones

### Step 0 — Repository and developer baseline

Deliver:

- GitHub remote configured and default branch confirmed.
- Monorepo folders: `apps/web`, `services/api`, `supabase`, `docs`, and `.github/workflows`.
- `.gitignore`, `.env.example` files, editor settings, and a short README.
- Local commands documented for Node, Go, Supabase CLI, and Docker prerequisites.

Local verification:

```text
git status --short
npm --version
go version
supabase --version
```

Acceptance: the repository is clean after the commit, the web and API hello-world commands run locally, and no secrets or Huawei data are present.

User verification: confirm the repository layout and preferred package manager before implementation continues.

### Step 1 — Local web/API vertical slice

Deliver:

- Next.js App Router shell using Tailwind and shadcn/ui.
- Go HTTP service with clean-architecture packages, health endpoint, request IDs, and JSON error envelope.
- OpenAPI contract for `/api/v1/health` and generated/typed web client.
- Local proxy/config so the web app calls the Go API without CORS workarounds.

Local verification:

```text
npm run lint
npm run typecheck
go test ./...
curl http://localhost:<api-port>/api/v1/health
```

Acceptance: landing page renders, the health endpoint returns a versioned response, and the web client displays API status.

User verification: inspect the first page and API response before authentication work begins.

### Step 2 — Supabase Auth, profiles, and RLS

Deliver:

- Local Supabase project with migrations for profiles and ownership policies.
- Email/password and Google OAuth flow with SSR cookies and PKCE.
- Go JWT/JWKS middleware and user-scoped repository interfaces.
- Account/session error states and sign-out behavior.

Local verification:

```text
supabase start
supabase db reset
npm run test:e2e -- auth
go test ./... -run Auth
```

Acceptance: a test user can register, confirm/sign in locally, call the Go API, and cannot read another user’s rows through either web or API paths.

User verification: verify the sign-in screens, Google-provider setup instructions, and privacy wording.

### Step 3 — Import manifest and resumable upload

Deliver:

- Browser/Web Worker folder or ZIP scanner.
- SHA-256 manifest, duplicate detection, 20 MiB part slicing, pause/resume/retry, and progress UI.
- Private Supabase Storage policies and import metadata tables.
- Go completion endpoint that accepts metadata only; Vercel is never used as a large-file proxy.

Local verification:

```text
npm run test:unit -- import
npm run test:e2e -- import-upload
go test ./... -run Import
```

Use generated fixtures, not the personal Huawei export. Include a fixture larger than the configured part size and assert that no HTTP request exceeds the documented limits.

Acceptance: a fixture folder/ZIP uploads in parts, resumes after a simulated failure, and creates one idempotent import job.

User verification: test the import wizard with a small synthetic export and approve the copy, progress states, and warning language.

### Step 4 — Huawei parser and canonical normalization

Deliver:

- Streaming JSON parser registry for health detail, sample sequence, sport-per-minute, and motion files.
- Canonical mappings for sleep, activity, calories, steps, standing, heart rate, HRV, stress, skin temperature, SpO2, and ECG summaries.
- Exact-file and record-level dedupe.
- Narrow repair/validation path for decimal keys in motion maps.
- Sanitized fixtures and parser error taxonomy.

Local verification:

```text
go test ./... -run Parser
go test ./... -run Dedup
go test ./... -run Motion
```

Acceptance: fixtures produce stable normalized rows, duplicate batches do not double-count, malformed motion fixtures are repaired only by the documented rule, and raw payloads are not persisted.

User verification: review the metric coverage matrix and the treatment of ECG waveform/RRI/GPS data.

### Step 5 — Legacy XLS backfill

Deliver:

- Tested legacy `.xls` reader adapter.
- Allowlist for selected SportsHealth sheets only.
- Historical backfill precedence: granular JSON first, legacy reports only for missing dates.
- Parser warnings for unsupported or ambiguous sheets.

Local verification:

```text
go test ./... -run LegacyXLS
go test ./... -run Backfill
```

Acceptance: sanitized `.xls` fixtures import approved sheets, preserve provenance, and never import membership, purchase, card, ranking, or agreement data.

User verification: review the historical date coverage and any fields intentionally excluded.

### Step 6 — First summary, goals, and dashboard

Deliver:

- First-import summary with date range, coverage, timezone, device, and data-quality warnings.
- Goal setup for steps, active minutes, workout frequency, sleep duration, and bedtime consistency.
- Dashboard cards, detail panels, 7/28/90-day reports, and responsive mobile layout.

Local verification:

```text
npm run lint
npm run typecheck
npm run test:e2e -- summary-goals-dashboard
```

Acceptance: a seeded local user can complete import → summary → goal → dashboard without manual database edits.

User verification: review the mobile-first dashboard hierarchy and approve the first visual direction using `docs/design/brand-and-ui-brief.md`.

### Step 7 — Scores, trends, suggestions, and safety copy

Deliver:

- Explainable score components: sleep 30%, activity 30%, recovery/cardio 25%, goal consistency 15%.
- Missing-data reweighting and coverage indicators.
- 28-day goal-completion forecast only; no medical prediction.
- Deterministic suggestions with evidence, confidence/coverage, and non-clinical disclaimer.

Local verification:

```text
go test ./... -run Scoring
npm run test:e2e -- reports-insights
```

Acceptance: score fixtures are deterministic, missing metrics are visible, and UI copy never presents a diagnosis or medical outcome.

User verification: approve score labels, thresholds, and suggestion tone before release.

### Step 8 — CI/CD, observability, deletion, and Vercel release

Deliver:

- GitHub Actions for lint/typecheck, Go tests, migration/RLS tests, parser fixtures, contract tests, and Playwright.
- Preview deploys against staging Supabase; production deploys only from protected `main`.
- Structured redacted logs, import job retries, deletion workflows, smoke tests, and rollback runbook.
- Two Vercel projects: Next.js web and Go API, with environment separation and deployment diagnostics.

Local verification:

```text
npm run build
go test ./...
supabase db lint
```

Acceptance: CI blocks unsafe changes, preview is isolated from production health data, smoke tests cover auth/API/import, and account/data deletion is verifiable.

User verification: approve the release checklist and domain mapping before production deployment.

## Handoff format for every step

The implementation thread should stop at each user verification gate and report:

1. milestone number and status;
2. files changed and migration names;
3. local commands and pass/fail output;
4. screenshots or a short browser walkthrough when UI changed;
5. privacy/security impact;
6. open decisions and the next exact approval request.

