# Delivery tracker

Last reviewed: 2026-07-19

This is the living status document. Update it at each meaningful handoff, accepted scope change, new blocker, pull-request transition, and release. Product intent belongs in `PROJECT_PLAN.md`; detailed change design belongs in a change plan.

## Current release

- Release target: private non-clinical V1.
- Current gate: Step 4 local worker foundation after the merged parser, scalar, sleep, activity, workout, motion-repair, and fuzz slices. Step 3's hosted synthetic two-user, quota/outage, and cleanup suite remains explicitly deferred and is out of scope.
- Current branch: `codex/step-4-worker-foundation`.
- Active milestone: Step 4 lease/checkpoint/retry/cleanup and owner-visible processing contracts. ADR 0005 Option A (dedicated non-browser worker identity) and a 24-hour raw-source recovery window are approved for source/local implementation; hosted identity, trigger, provider, and secret configuration remain gated.
- Active Step 4 plan: [`plans/0004-huawei-json-normalization.md`](plans/0004-huawei-json-normalization.md).
- The Go foreground access decision is accepted in [`decisions/0002-foreground-supabase-access.md`](decisions/0002-foreground-supabase-access.md). Preview isolation is required before hosted verification (3I).
- Production status: not provisioned and not approved for user data.

## Milestones

| Step | Outcome | Status | Current exit evidence / next gate |
| --- | --- | --- | --- |
| 0 | Repository and developer baseline | Done on `main` | Repository structure and local commands established |
| 1 | Local Next.js/Go vertical slice | Done on `main` | Web/API baseline merged in PR #1 |
| 2 | Supabase Auth, profiles, SSR sessions, JWT verification, and RLS | Done | Local email via Mailpit and Google login verified; PR #2 merged after Documentation, Web, and API checks passed |
| 3 | Manifest, private multipart/resumable upload, import records/jobs, progress/recovery | Handoff PR #16 open | User accepted local browser evidence plus hosted Google Auth and authenticated upload-to-queue. Hosted synthetic two-user RLS, quota/outage, and cleanup smoke is deferred and remains a recorded operational risk |
| 4 | Streaming Huawei JSON parsing, normalization, provenance, and dedupe | Worker foundation in progress | PRs #17-#23 merged: parser, scalar/sleep/activity/workout mappings, motion repair, fuzz hardening. Next gate is local worker lease/checkpoint/retry/cleanup proof; ECG/RRI and GPS remain discarded |
| 5 | Legacy XLS allowlisted backfill and precedence | Planned | Parser library spike and sanitized fixture acceptance |
| 6 | First summary, goals, reports, and dashboard | Planned | Normalized data contracts and UX acceptance |
| 7 | Explainable scores, trends, deterministic suggestions, and safety copy | Planned | Metric coverage and threshold decisions |
| 8 | Security/privacy hardening, deletion, diagnostics, CI expansion, and operational readiness | Planned | Production-readiness review and observability/provider decisions |
| 9 | Hosted staging/production integration, migration/deployment automation, launch, and rollback proof | Planned | Completed release record and explicit production approval |

`Done` means the user has accepted the outcome, the pull request is merged, and the tracker contains the resulting evidence.

## Step 3 work-package baseline

This baseline is implemented through the active change plan. The default is one
accepted milestone slice per pull request; a split requires either user request
or a documented independent compatibility, release, or review boundary.

| ID | Work package | Dependencies | Completion evidence |
| --- | --- | --- | --- |
| 3A | Define import API/OpenAPI contract, manifest version, state machine, error taxonomy, limits, and idempotency keys | Step 2 merge | Complete in PR #3 and extended by PR #7 |
| 3B | Add `import_runs`, files, parts, jobs, errors, required grants, RLS, indexes, and retention metadata | 3A | Complete in PRs #3/#7; 38 pgTAP checks include invoker RPC paging/idempotency and cross-owner denial |
| 3C | Add private Storage bucket/path policies and upload authorization design | 3A, 3B | Complete in PRs #3/#7; corrected owner path passed real local TUS create/upload/verify/delete |
| 3D | Build Web Worker folder/ZIP scanner, classification, SHA-256 manifest, duplicate detection, and cancellation | 3A | Complete in PRs #4-#6 plus generated ZIP browser selection and changing-source unit evidence |
| 3E | Build bounded part upload with checksum, retry/backoff, pause/resume, persisted client state, and max concurrency | 3C, 3D | Complete in PRs #8/#9; generated multi-chunk ZIP passed pause, refresh/reselect, deterministic TUS resume, checksum, queue, and cleanup in real Chromium |
| 3F | Add Go manifest/completion endpoints, user scope, validation, idempotent job creation, and structured redacted logs | 3A, 3B | Complete in merged PR #7 (`674f364`): bounded create/page/status/complete/delete, user-JWT/RLS adapter, idempotent job, and redacted two-user local probe |
| 3G | Build import wizard states: instructions, review, upload, recovery, completion, warning, cancel, and cleanup | 3D, 3E, 3F | Complete in PRs #8/#9; 390x844 Chromium flow verifies keyboard focus order, ARIA progress state, interruption recovery, queue, and cancel/delete messaging |
| 3H | Add abandoned/failed upload cleanup and import deletion path | 3B, 3C, 3F | Complete in PR #9 for caller-owned reconciliation and deletion; system-wide scheduling is deferred to the Step 4 worker decision |
| 3I | Provision or document staging integration and run browser-to-Storage-to-job smoke | INT-001/002, 3A-3H | Shared staging accepted; migrations/security baseline and Vercel targets configured; user completed hosted Google Auth and authenticated upload-to-queue. Synthetic two-user RLS, quota/outage, and cleanup smoke deferred by user acceptance |

### Step 3 non-goals

- Parsing Huawei metric payloads beyond file classification and job handoff (Step 4).
- Legacy XLS normalization (Step 5).
- Production Supabase/Vercel launch (Step 9).
- Uploading through a Vercel request body or persisting an original archive after approved cleanup.

### Step 3 release/rollback shape

- Schema additions are expand-only and remain unused until the web/API slice is enabled.
- UI can keep import entry disabled until API, Storage policies, cleanup, and recovery states are green.
- Rollback disables import initiation and rolls web/API deployments back; added tables/objects remain for forward cleanup.
- Failed or abandoned synthetic uploads must be deletable without deleting another user's objects.

## Open decisions

| ID | Decision | Owner | Needed by | State |
| --- | --- | --- | --- | --- |
| DEC-001 | Use shared staging Supabase initially or adopt per-PR Supabase Branching | User/release owner | Step 3 hosted verification | Open; active `Health_Tracking` project is the candidate shared staging target pending explicit confirmation |
| DEC-002 | Use Vercel custom Staging or branch-specific Preview as the stable release-candidate target | User/release owner | First hosted staging setup | Open; branch-specific Preview fallback |
| DEC-003 | Select transactional Auth SMTP provider and sending domain | User/product owner | External beta/Step 9 | Open |
| DEC-004 | Select production web/API domains and DNS owner | User/product owner | Step 9 | Open |
| DEC-005 | Select redacted error monitoring, tracing, and uptime approach | User/engineering owner | Step 8 | Open |
| DEC-006 | Select paid plan capabilities for backups, branching, quotas, and production availability | User/billing owner | Production readiness | Open; do not assume paid features |
| DEC-007 | Select Go foreground and background Supabase access model without weakening RLS | User/engineering owner | Step 3 API persistence / Step 4 worker | Foreground accepted in ADR 0002; ADR 0005 Option A approved for local foundation, hosted identity/trigger pending |

Accepted architectural decisions receive an ADR in [`decisions/`](decisions/).

## Risk register

| ID | Risk | Likelihood/impact | Mitigation and trigger | State |
| --- | --- | --- | --- | --- |
| R-001 | Auth-enabled Vercel preview redirects to the wrong origin because `NEXT_PUBLIC_APP_URL` is static | Medium/high | Branch-specific value or reviewed trusted-host implementation before preview Auth | Open |
| R-002 | Shared staging branches interfere through users, migrations, jobs, or Storage objects | Medium/medium | Synthetic data, owner scoping, serialized migrations; adopt Supabase Branching if collision cost grows | Open |
| R-003 | Large upload exceeds browser memory, Storage, quota, or platform request limits | Medium/high | Streaming/part tests, 20 MiB cap, bounded concurrency, quota audit, direct Storage path | Step 3 control |
| R-004 | Raw Huawei/health/GPS/ECG content leaks through fixtures, logs, screenshots, or telemetry | Medium/critical | Generated/sanitized fixtures, redaction tests, no raw payload persistence, review evidence | Continuous |
| R-005 | Hosted email Auth is unreliable or restricted without custom SMTP | High/high before launch | Select provider, domain authentication, deliverability/rate-limit tests, Google fallback | Open |
| R-006 | CI proves documentation, web build, Go baseline, local migration/RLS tests, and generated browser import E2E; repository-wide dependency/security scanning is not required | Medium/high before launch | Keep the browser gate required and add dependency/secret scanning before Step 9 | Reduced; open |
| R-007 | Application rollback is incompatible with a database migration | Medium/high | Expand/migrate/contract, staging compatibility tests, forward-repair runbook | Continuous |
| R-008 | Next.js 16.2.10 currently brings a PostCSS advisory without a non-breaking stable npm-audit resolution | Medium/medium | Track upstream fixed release, avoid untrusted runtime CSS stringification, and verify upgrade through Step 8 dependency review; do not apply npm's breaking downgrade suggestion | Open |
| R-009 | Hosted synthetic two-user, quota/outage, and cleanup smoke remains incomplete | Medium/high | Preserve local RLS/cleanup acceptance and run the deferred hosted suite before external beta or production release | Deferred by user acceptance; do not treat as production evidence |

## Evidence log

| Date | Scope | Evidence | Result |
| --- | --- | --- | --- |
| 2026-07-15 | Step 2 local Auth | Email confirmation through Mailpit, email/password login, Google OAuth, account profile read | User accepted |
| 2026-07-15 | Step 2 CI fix | PR #2 `Web checks` and `API checks` for `5fdefca` | Green; merge pending |
| 2026-07-16 | Step 2 merge | PR #2 Documentation, Web, and API checks | Green; squash-merged as `0b3ad3d` |
| 2026-07-16 | Step 3 local 3A-3C | `migration up --local`, pgTAP owner isolation (19 tests), and `db lint` | Green; source bytes remain out of API/database metadata |
| 2026-07-16 | Step 3 local 3D slice | Worker directory review, synthetic scanner/ZIP-stream tests, authenticated import-review redirect | Green locally; no upload or ZIP UI enabled |
| 2026-07-16 | Step 3 local ZIP review | Worker ZIP stream, synthetic traversal rejection, unit tests, and production build | Green locally; no upload or source retention enabled |
| 2026-07-16 | Step 3 scanner recovery | Exact duplicate grouping, explicit cancel action/state, and nine scanner tests | Green locally; browser Worker interaction pending PR/CI verification |
| 2026-07-16 | Step 3 merge status correction | PR #3 (`ca6255f`), PR #4 (`89c2712`), PR #5 (`b7283d2`), and PR #6 (`be7e18c`) are present on `main` | Merged; these are completed delivery slices, not the complete Step 3 milestone |
| 2026-07-16 | Step 3 API/RLS persistence | Forward Storage policy fix, paged security-invoker RPCs, 38 pgTAP checks, Go API test/vet, and redacted two-user API probe | Green locally; direct TUS and browser E2E still pending |
| 2026-07-16 | Step 3 API merge | PR #7 (`674f364`) merged after all GitHub checks passed | 3F complete; main remains fail-closed for direct upload |
| 2026-07-16 | Step 3 direct TUS slice | Pinned `tus-js-client` 4.3.1, deterministic resume, source/part checksum validation, 6 MiB transport chunks, 20 MiB logical objects, 1 MiB-safe manifest paging, and generated-byte local create/upload/complete/delete probe | Green locally; feature gated, ZIP adapter/browser interruption evidence/hosted proof remain |
| 2026-07-16 | Step 3 direct TUS merge | PR #8 (`268e087`) merged after Documentation, Web, API, and Supabase checks passed | Directory upload remains fail-closed by default; Step 3 continues |
| 2026-07-16 | Step 3 ZIP/cleanup slice | Bounded ZIP part stream, archive/part revalidation, expired owner-run cleanup endpoint, direct metadata writes revoked, ADR 0004, 19 web tests, 46 pgTAP checks, and synthetic cleanup convergence | Green locally; browser interruption/accessibility and hosted staging evidence remain |
| 2026-07-16 | Step 3 ZIP/cleanup merge | PR #9 (`b79d63e`) merged after all required checks passed | All Step 3 implementation PRs #3-#9 are merged; only environment/browser acceptance remains |
| 2026-07-17 | Step 4 planning baseline | Detailed normalization plan, source-coverage matrix, and proposed background-worker access ADR | Drafted on `codex/step-4-plan`; implementation has not started |
| 2026-07-17 | Step 4 planning merge | PR #10 (`741a2ea`) passed Documentation, Web, API, and Supabase checks | Merged; Step 4 implementation remains gated by acceptance of ADR 0005 and the source matrix |
| 2026-07-17 | Step 3 real-browser acceptance | Pinned Playwright 1.61.1; generated 8 MiB ZIP; email/password SSR session; 390x844 keyboard/ARIA review; pause, reload/reselect resume, direct local TUS, one queued job, second-user 404, cancel/delete, and zero residual users/objects | Green locally; test exposed and fixed static browser bundling of `NEXT_PUBLIC_SUPABASE_URL`; hosted 3I remains |
| 2026-07-17 | Step 3 browser CI gate | PR #11 head `f2c0016`: existing schema lint/46 pgTAP checks followed by Chromium Auth/import pause-resume and cancel-cleanup scenarios on Linux | Green in `Supabase schema and RLS checks` (4m40s); final PR rerun/merge pending |
| 2026-07-17 | Step 3 browser acceptance merge | PR #11 passed Documentation, Web, API, and extended Supabase/browser checks | Squash-merged as `5e58993`; local and CI browser gates are complete |
| 2026-07-17 | Hosted provider audit | Supabase `Health_Tracking` is active/healthy in `ap-southeast-1`; migration list is empty; Security Advisor reports anon/authenticated execution of `public.rls_auto_enable()`; Vercel team has zero projects | Candidate only; no keys read and no provider mutation performed |
| 2026-07-19 | Hosted staging setup | Canonical repository migrations applied and migration history aligned; public execution revoked for `rls_auto_enable()` and profile trigger helper; all application tables report RLS enabled; Security Advisor pre-existing warning cleared | Green; seven intentional authenticated-only definer RPC notices remain |
| 2026-07-19 | Hosted preview deployment | Vercel projects `health-tracking-api-staging` and `health-tracking-web-staging` configured with preview-only Supabase/API values; API health 200 and web 200; unauthenticated `/me`, `/imports`, and malformed import route return 401 | Green; no production project or user data |
| 2026-07-19 | Step 4 first local slice | PR #17 (`a2e904f`) added sanitized fixture, pure streaming parser, scalar schema/API contract, deterministic dedupe/provenance, and local privacy/RLS tests | User accepted; ECG/RRI and GPS remain discarded |
| 2026-07-19 | Step 4 merged parser/mapping hardening | PRs #18-#23 merged scalar provenance, sleep, activity, workout summaries, narrow motion repair, strict JSON, chunk invariance, and Go fuzz coverage | Required CI green; no raw ECG/RRI or GPS routes persisted |
| 2026-07-19 | Step 4 worker decision | ADR 0005 Option A approved; raw-source recovery window fixed at 24 hours | Local lease/checkpoint/retry/cleanup foundation authorized; hosted worker identity, trigger, and secrets remain pending |
| 2026-07-19 | Hosted synthetic smoke attempt | Two synthetic signup attempts used reserved/non-personal domains; provider rejected the first as invalid (400) and then rate-limited requests (429). Bounded unauthenticated API checks remain fail-closed; cleanup query reports zero expired candidates | Authenticated upload, cross-user denial, quota, and authenticated cleanup evidence blocked by Auth rate limit; no tokens or payloads recorded |
| 2026-07-19 | Hosted staging PR | PR #14 opened from `codex/step-3-hosted-staging` with migration and non-sensitive evidence; Documentation, Web, and API checks green | Supabase schema/RLS check pending; do not merge until required CI completes |
| 2026-07-19 | Step 3 final acceptance | Local synthetic browser suite passed upload pause/resume, refresh/reselect, owner denial, cancel, and cleanup; user completed hosted Google Auth and authenticated upload-to-queue; aggregate staging state reports one queued import | User accepted Step 3 handoff; hosted synthetic two-user RLS, quota/outage, and cleanup smoke is deferred, not passed |

Do not record credential values, email addresses, raw health content, or private incident details in this log.

## Change log

| Date | Change | Reason |
| --- | --- | --- |
| 2026-07-15 | Split operational hardening (Step 8) from production integration/release (Step 9) | Production environments, providers, migrations, release, and rollback require an independent acceptance gate |
| 2026-07-15 | Added work-package, environment, integration, risk, evidence, and change-control structure | Earlier milestone prose did not expose provider/setup and production-readiness work |
| 2026-07-16 | Began Step 3 local foundation after Step 2 merge | Establish owner-isolated import metadata and private Storage boundaries before scanner or uploader code |
