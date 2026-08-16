# Change plan: Step 6 summary, dashboard, and reports

## Metadata

- Change ID: 0006
- Milestone/work package: Step 6 summary/dashboard/reports slice
- Owner: Health Tracking engineering
- Status: implementation complete; PR merge and hosted verification pending
- Baseline commit: `bc546e6`
- Branch: `codex/step-6-summary-dashboard-reports`
- Related issue/PR/ADR: none yet
- Target environments: local / CI / staging
- Requested/last updated date: 2026-08-16

## Outcome

After a private import is processed, the signed-in owner can open Summary,
Dashboard, and Reports and see bounded 7/28/90-day wellness coverage and
quality information, including timezone, source families, warnings, and
partial or empty states. The API and database contract is owner-scoped and
does not expose source paths, payloads, or medical claims. The landing page
keeps the current SSR session, authenticated entry points land on Dashboard,
and the import completion state links back to Dashboard and Profile. The
worker also accepts the observed Huawei activity-array export shape through a
bounded safe adapter that discards raw route/detail fields.

### Success measures

- A staged import with normalized rows produces a non-error summary response.
- The reviewed Huawei activity-array export produces owner-scoped workout rows
  without retaining its raw `attribute` route/detail field.
- Summary, Dashboard, and Reports are real authenticated routes with loading,
  empty, partial, error, and unauthorized behavior.
- Date windows are bounded to 7, 28, or 90 days and use the profile/import
  timezone for canonical days.
- Cross-owner reads are denied by the database contract and API boundary.
- The identified zero-byte verified source is completed with a warning instead
  of failing the entire worker job.

### Non-goals

- Goal CRUD, scores, trends, suggestions, diagnosis, treatment, or medical
  interpretation.
- Production provisioning, production deployment, new third-party providers,
  automatic scheduling, or changing hosted secrets beyond the reviewed
  temporary staging worker gate.
- Retaining raw source names, paths, payloads, or health values in logs.

## User and failure flows

An authenticated user visits `/summary`, `/dashboard`, or `/reports`; the web
server confirms the Supabase session, the browser calls the owner-scoped Go
API, and the API reads the bounded summary RPC. A missing session redirects to
sign-in. No normalized data shows an explicit empty state. Partial coverage
shows available metrics and the missing-data explanation. API/database errors
show a retry-safe error state without diagnostic details.

### Acceptance scenarios

1. Given a completed import with normalized rows, when the owner opens Summary,
   then timezone, coverage, warnings, and a 7-day metric view render.
2. Given the same owner, when Dashboard or Reports is opened, then the route
   renders the same bounded owner data in its page-specific hierarchy.
3. Given no normalized rows, when a route is opened, then an empty/partial
   explanation renders instead of a generic import failure.
4. Given another user's access token, when the summary RPC is called, then no
   rows or aggregate values for the first owner are returned.
5. Given a verified zero-byte source file, when the worker runs, then that file
   is checkpointed with `empty_source_excluded` and the import can complete
   with warnings.

## Scope and impact matrix

| Area | Change? | Detail / owning work package |
| --- | --- | --- |
| Next.js UI/routes/server actions | Yes | Authenticated Summary, Dashboard, Reports pages, shared navigation/view states, session-aware landing, and import/profile links |
| Go API/domain/repository | Yes | Owner-scoped `GET /api/v1/summary?window=7|28|90` contract |
| OpenAPI/client contract | Yes | Typed summary response and browser API client |
| Postgres schema/index/grant/RLS | Yes | Summary RPC, bounded date/index support, explicit authenticated execute grant |
| Supabase Auth/JWT | No | Existing session/JWT boundary reused |
| Supabase Storage/policies | No | Existing private source path reused |
| Background jobs/cron | Yes | Empty-source worker handling only; no scheduler |
| Third-party provider console | No | No new provider work |
| Environment variables/secrets | No | Existing API/web variables only; reviewed temporary worker gate restored off |
| Logging/metrics/alerts | Yes | Redacted request/summary diagnostics only |
| Privacy/retention/deletion | Yes | Aggregate response excludes raw paths/payloads and remains owner-cascaded |
| Documentation/support | Yes | This plan and delivery evidence |

## Dependencies and decisions

| Item | Type | Owner | Needed by | State / default |
| --- | --- | --- | --- | --- |
| Steps 4-5 normalized tables | dependency | engineering | API/RPC | present |
| Profile timezone fallback | dependency | engineering | date aggregation | use profile, then import timezone, then UTC |
| Goal CRUD | scope decision | user/product | Step 6 full milestone | deferred from this requested slice |

## Design and contracts

### Data/API/state contract

`GET /api/v1/summary?window=7|28|90` requires a valid Supabase user JWT.
The response contains only owner-scoped aggregates and safe metadata:

```json
{
  "window_days": 7,
  "timezone": "Asia/Bangkok",
  "coverage": {"first_day": "2026-08-01", "last_day": "2026-08-07", "days_with_data": 3},
  "quality": {"import_state": "completed_with_warnings", "warning_codes": ["empty_source_excluded"]},
  "metrics": [{"day": "2026-08-07", "steps": 4200, "active_minutes": 31, "sleep_minutes": 418, "workouts": 1, "heart_rate_samples": 24}]
}
```

The server clamps no arbitrary dates: only 7, 28, and 90 are accepted, and
the SQL function limits returned daily rows to the selected window. Values are
summary metrics, not clinical interpretations.

### Data lifecycle

- Read: profile, import metadata/job warnings, canonical samples/sleep,
  activity, workout, and legacy quality counts through the owner-scoped RPC.
- Owner/user-scope key: `auth.uid()` derived inside SQL; no user ID is accepted
  from the browser.
- Provenance: source family and warning codes only; no raw file metadata in the
  response.
- Delete/backfill: existing import/account cascade behavior remains unchanged.

### Migration plan

- Migration name: `20260816090000_add_step6_summary_contract.sql`.
- Expand-only: add indexes/function/grants; no destructive rewrite.
- Staging: apply migration, repair the reviewed failed staging job through a
  narrowly scoped forward SQL transition, rerun the worker with its gate
  enabled only for the reviewed run, then redeploy with the gate off.
- Production: stop; production is not provisioned or approved.
- Rollback: redeploy the prior web/API build; retain the additive SQL function
  for forward compatibility.

## Environment and secret delta

No new variables or credentials. The temporary staging worker trigger secret
rotation/gate is operationally reviewed, automatically restored off, and is
not committed or reported with values.

## Third-party integration delta

No new provider integration. Staging Supabase and Vercel are used only for the
requested non-production verification.

## Security and privacy review

- [x] Authentication and authorization boundary identified.
- [x] Owner access and cross-user denial tests defined.
- [x] RLS, explicit grants, and Storage operation policies reviewed.
- [x] No secret is browser-visible, logged, committed, or copied into evidence.
- [x] Raw health/source payload logging is prohibited.
- [x] Non-clinical wording and product safety boundary reviewed.

Threats/mitigations: SQL derives the owner from `auth.uid()`; window input is
allowlisted; the UI renders only aggregate fields; worker empty-source handling
marks a warning and never reads a nonexistent object.

## Work packages

| ID | Deliverable | Dependencies | Verification | Status |
| --- | --- | --- | --- | --- |
| A | Empty verified-source worker handling | Step 4 worker | Go regression test plus reviewed staging run | complete |
| B | Summary RPC, API contract, grants, and tests | normalized schema | migration/RLS/API tests | complete |
| C | Summary/Dashboard/Reports UI and typed client | API contract | web build/unit/browser smoke | complete; hosted auth pending |
| D | Staging migration, repair, worker replay, and deployment | A-C | redacted staging evidence | complete; final replay/deploy pending |

## Test plan

| Layer/scenario | Fixture/data | Command or procedure | Expected result | Evidence location |
| --- | --- | --- | --- | --- |
| Unit | synthetic worker source with zero logical bytes | `go test ./...` | warning completion, no parse failure | test output |
| API/contract | synthetic summary response | Go HTTP handler tests | allowlisted windows and stable JSON | test output |
| Migration/RLS | generated owner rows | Supabase reset/pgTAP or SQL checks | owner-only aggregates and grants | test output |
| Browser/E2E | sanitized seeded normalized rows | local browser or staging route | all three pages render states | redacted screenshot/log |
| Provider/staging | existing staging import | reviewed worker trigger and API checks | import completes with warnings; gate off afterward | redacted staging log |
| Failure/recovery | empty/partial/no-data states | API/UI tests | clear retry/partial/empty copy | test output |

## Observability and support

Safe fields are request ID, route, window days, row counts, import state, and
warning codes. Prohibited fields are email, raw health values, source names,
paths, payloads, tokens, and full provider responses.

## Rollout and rollback

Apply the additive migration before the API deployment, deploy the API, deploy
the web project, then verify the authenticated routes. The worker trigger gate
must remain false outside the reviewed staging run. Stop if migration, owner
scope, or API health checks fail.

## Evidence and handoff

- Go: `go test ./...` and `go vet ./...` passed, including zero-byte,
  unsupported-shape, and Huawei activity-array worker regressions plus summary
  handler window/auth tests.
- Web: lint, typecheck, 21 unit tests, and `npm run build` passed; the build exposes dynamic
  `/summary`, `/dashboard`, and `/reports` routes.
- Staging Supabase: migration applied; `summary_api_snapshot` exists with
  `authenticated` execute and `anon` execute revoked.
- Reviewed worker replay: 63 verified files processed, replay returned `idle`,
  warnings were `empty_source_excluded`, `source_schema_unsupported`,
  `xls_sheet_excluded`, and `xls_sheet_unknown`; normalized record count is
  currently 0, so the hosted UI must show its explicit empty/partial state.
- Staging deployments: API restore deployment `dpl_HVPhb7yPxjqmcfQartpt1EJQgPZv`
  and final web deployment `dpl_HTJ46hzyy4puB3XxNx6Eksjr9NT7` are ready and
  aliased.
- Production approval is explicitly not requested by this plan.

## Change history

| Date | Proposed delta | Impact | Decision/approver |
| --- | --- | --- | --- |
| 2026-08-16 | Initial requested Step 6 summary/dashboard/reports slice | staging only, additive schema/API/UI | user request |
| 2026-08-16 | Follow-up UX/session and Huawei activity-array worker fix | same Step 6 branch/PR; staging replay and deployment authorized | user request |
