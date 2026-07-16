# Delivery tracker

Last reviewed: 2026-07-15

This is the living status document. Update it at each meaningful handoff, accepted scope change, new blocker, pull-request transition, and release. Product intent belongs in `PROJECT_PLAN.md`; detailed change design belongs in a change plan.

## Current release

- Release target: private non-clinical V1.
- Current gate: Step 2 is user-accepted and pull request [#2](https://github.com/phukaokub/Health_Tracking/pull/2) is open, mergeable, and green for `Web checks` and `API checks` at commit `5fdefca`.
- Current branch: `codex/complete-step-2`.
- Next milestone: Step 3, import manifest and resumable upload.
- Proposed Step 3 plan: [`plans/0003-import-manifest-upload.md`](plans/0003-import-manifest-upload.md).
- Before Step 3 starts: merge Step 2, accept the Step 3 change plan and Go foreground Supabase access model, and decide how the first hosted preview isolates Supabase data/migrations. Local-only Step 3 work may proceed before hosted provisioning if the hosted dependency is explicitly deferred to its integration work package.
- Production status: not provisioned and not approved for user data.

## Milestones

| Step | Outcome | Status | Current exit evidence / next gate |
| --- | --- | --- | --- |
| 0 | Repository and developer baseline | Done on `main` | Repository structure and local commands established |
| 1 | Local Next.js/Go vertical slice | Done on `main` | Web/API baseline merged in PR #1 |
| 2 | Supabase Auth, profiles, SSR sessions, JWT verification, and RLS | Accepted; in review | Local email via Mailpit and Google login verified; PR #2 checks green; merge pending |
| 3 | Manifest, private multipart/resumable upload, import records/jobs, progress/recovery | Planned; next | Step 3 change plan and preview-isolation decision |
| 4 | Streaming Huawei JSON parsing, normalization, provenance, and dedupe | Planned | Sanitized mapping/fixture review after Step 3 job boundary |
| 5 | Legacy XLS allowlisted backfill and precedence | Planned | Parser library spike and sanitized fixture acceptance |
| 6 | First summary, goals, reports, and dashboard | Planned | Normalized data contracts and UX acceptance |
| 7 | Explainable scores, trends, deterministic suggestions, and safety copy | Planned | Metric coverage and threshold decisions |
| 8 | Security/privacy hardening, deletion, diagnostics, CI expansion, and operational readiness | Planned | Production-readiness review and observability/provider decisions |
| 9 | Hosted staging/production integration, migration/deployment automation, launch, and rollback proof | Planned | Completed release record and explicit production approval |

`Accepted` is intentionally distinct from `Done`: Step 2 is accepted by the user but remains open until its pull request is merged and the tracker records that merge.

## Step 3 work-package baseline

This baseline becomes a dedicated change plan before implementation. Work packages may be split into separate pull requests if each keeps `main` safe and the dependencies remain explicit.

| ID | Work package | Dependencies | Completion evidence |
| --- | --- | --- | --- |
| 3A | Define import API/OpenAPI contract, manifest version, state machine, error taxonomy, limits, and idempotency keys | Step 2 merge | Reviewed contract examples and invalid/duplicate request tests |
| 3B | Add `import_runs`, files, parts, jobs, errors, required grants, RLS, indexes, and retention metadata | 3A | Clean reset/lint; owner CRUD and cross-user denial tests |
| 3C | Add private Storage bucket/path policies and upload authorization design | 3A, 3B | Owner create/read/delete; cross-user and path-tamper denial; upsert operations tested separately |
| 3D | Build Web Worker folder/ZIP scanner, classification, SHA-256 manifest, duplicate detection, and cancellation | 3A | Unit fixtures including duplicates, empty/unsupported files, cancellation, and no raw data logging |
| 3E | Build bounded part upload with checksum, retry/backoff, pause/resume, persisted client state, and max concurrency | 3C, 3D | Synthetic multi-part fixture, network interruption, resume, checksum mismatch, request-size assertion |
| 3F | Add Go manifest/completion endpoints, user scope, validation, idempotent job creation, and structured redacted logs | 3A, 3B | API/domain tests for valid, unauthorized, tampered, duplicate, and partial manifests |
| 3G | Build import wizard states: instructions, review, upload, recovery, completion, warning, cancel, and cleanup | 3D, 3E, 3F | Browser walkthrough and E2E with accessible/mobile states |
| 3H | Add abandoned/failed upload cleanup and import deletion path | 3B, 3C, 3F | Idempotent cleanup tests and object/metadata deletion evidence |
| 3I | Provision or document staging integration and run browser-to-Storage-to-job smoke | INT-001/002, 3A-3H | Environment audit, synthetic hosted E2E, quota/failure result, no production data |

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
| DEC-001 | Use shared staging Supabase initially or adopt per-PR Supabase Branching | User/release owner | Step 3 hosted verification | Open; shared synthetic staging is default |
| DEC-002 | Use Vercel custom Staging or branch-specific Preview as the stable release-candidate target | User/release owner | First hosted staging setup | Open; branch-specific Preview fallback |
| DEC-003 | Select transactional Auth SMTP provider and sending domain | User/product owner | External beta/Step 9 | Open |
| DEC-004 | Select production web/API domains and DNS owner | User/product owner | Step 9 | Open |
| DEC-005 | Select redacted error monitoring, tracing, and uptime approach | User/engineering owner | Step 8 | Open |
| DEC-006 | Select paid plan capabilities for backups, branching, quotas, and production availability | User/billing owner | Production readiness | Open; do not assume paid features |
| DEC-007 | Select Go foreground and background Supabase access model without weakening RLS | User/engineering owner | Step 3 API persistence / Step 4 worker | Open; foreground user JWT + publishable key is proposed, worker credential deferred |

Accepted architectural decisions receive an ADR in [`decisions/`](decisions/).

## Risk register

| ID | Risk | Likelihood/impact | Mitigation and trigger | State |
| --- | --- | --- | --- | --- |
| R-001 | Auth-enabled Vercel preview redirects to the wrong origin because `NEXT_PUBLIC_APP_URL` is static | Medium/high | Branch-specific value or reviewed trusted-host implementation before preview Auth | Open |
| R-002 | Shared staging branches interfere through users, migrations, jobs, or Storage objects | Medium/medium | Synthetic data, owner scoping, serialized migrations; adopt Supabase Branching if collision cost grows | Open |
| R-003 | Large upload exceeds browser memory, Storage, quota, or platform request limits | Medium/high | Streaming/part tests, 20 MiB cap, bounded concurrency, quota audit, direct Storage path | Step 3 control |
| R-004 | Raw Huawei/health/GPS/ECG content leaks through fixtures, logs, screenshots, or telemetry | Medium/critical | Generated/sanitized fixtures, redaction tests, no raw payload persistence, review evidence | Continuous |
| R-005 | Hosted email Auth is unreliable or restricted without custom SMTP | High/high before launch | Select provider, domain authentication, deliverability/rate-limit tests, Google fallback | Open |
| R-006 | CI currently proves documentation, web build, and Go baselines, not migrations/RLS/E2E/repository-wide security | High/high before launch | Add gates with Steps 3-8 and make them required before Step 9 | Open |
| R-007 | Application rollback is incompatible with a database migration | Medium/high | Expand/migrate/contract, staging compatibility tests, forward-repair runbook | Continuous |

## Evidence log

| Date | Scope | Evidence | Result |
| --- | --- | --- | --- |
| 2026-07-15 | Step 2 local Auth | Email confirmation through Mailpit, email/password login, Google OAuth, account profile read | User accepted |
| 2026-07-15 | Step 2 CI fix | PR #2 `Web checks` and `API checks` for `5fdefca` | Green; merge pending |

Do not record credential values, email addresses, raw health content, or private incident details in this log.

## Change log

| Date | Change | Reason |
| --- | --- | --- |
| 2026-07-15 | Split operational hardening (Step 8) from production integration/release (Step 9) | Production environments, providers, migrations, release, and rollback require an independent acceptance gate |
| 2026-07-15 | Added work-package, environment, integration, risk, evidence, and change-control structure | Earlier milestone prose did not expose provider/setup and production-readiness work |
