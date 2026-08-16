# Change plan: Step 6 summary, goals, dashboard, and reports

## Metadata

- Change ID: 0006
- Milestone/work package: Step 6 — first summary, goals, dashboard, and reports
- Owner: engineering
- Status: implementation complete; user acceptance pending
- Baseline commit: bc546e6
- Branch: codex/step-6-summary-goals
- Related issue/PR/ADR: none
- Target environments: local / CI / preview or non-production staging
- Requested/last updated date: 2026-08-15

## Outcome

An authenticated user can review the result of an import, confirm the timezone
used for daily grouping, set and archive wellness goals, and inspect a bounded
7/28/90-day dashboard/report without diagnosis or raw-source exposure.

### Success measures

- Owner-scoped report data is returned through one bounded Supabase RPC.
- Summary, dashboard, and reports show explicit empty and partial-data states.
- Goal and timezone changes are validated inside authenticated Server Actions.
- The local browser can complete summary → goals → dashboard → reports using
  generated/sanitized data.

### Non-goals

- Step 7 scoring, forecasts, deterministic suggestions, or medical wording.
- ECG waveform/RRI/GPS display; ECG is explicitly unavailable in this release.
- Production provider setup, automatic jobs, analytics providers, or unrelated
  refactors.

## User and failure flows

- Authenticated users land on `/summary`, then can navigate to `/goals`,
  `/dashboard`, and `/reports`.
- Empty imports show an explanation and a link back to import.
- Partial coverage labels which metrics are present instead of filling gaps with
  zeros without context.
- Invalid goal values or timezones return a safe validation message.
- Unauthenticated page access redirects to sign-in; RPCs and Server Actions
  re-check the authenticated caller.
- Database/query failures render a safe retry message without raw error detail.

### Acceptance scenarios

1. Given an authenticated seeded user, when `/summary` is opened, then the
   imported range, coverage, source summary, timezone, and warnings are shown.
2. Given an authenticated user, when a valid goal is saved or archived, then
   the owner sees the updated goal and another user cannot read or mutate it.
3. Given a 7/28/90-day selection, when `/dashboard` or `/reports` is opened,
   then the bounded daily data and partial/empty states are rendered.

## Scope and impact matrix

| Area | Change? | Detail / owning work package |
| --- | --- | --- |
| Next.js UI/routes/server actions | Yes | Summary, goals, dashboard, reports, timezone confirmation |
| Go API/domain/repository | No | Existing import API remains unchanged |
| OpenAPI/client contract | No | Supabase RPC and typed server DAL are the Step 6 query contract |
| Postgres schema/index/grant/RLS | Yes | Goals table, owner RLS, bounded report RPC |
| Supabase Auth/JWT | No | Existing SSR session and RLS boundary reused |
| Supabase Storage/policies | No | Existing private import lifecycle reused |
| Background jobs/cron | No | Reports query normalized rows at request time |
| Third-party provider console | No | No new provider or secret |
| Environment variables/secrets | No | Existing variables only |
| Logging/metrics/alerts | Minimal | Safe query failure messages only |
| Privacy/retention/deletion | Yes | Goals cascade with account deletion; no raw source data added |
| Documentation/support | Yes | Plan, tracker, and plan index |

## Dependencies and decisions

| Item | Type | Owner | Needed by | State / default |
| --- | --- | --- | --- | --- |
| Step 4–5 normalized tables | dependency | engineering | implementation | available on `main` |
| Profile timezone | dependency | engineering | summary/report grouping | existing profile value; validated on update |
| Report range limit | decision | engineering | RPC contract | 1–90 days, inclusive |
| Device detail | decision | product | summary | show source-family coverage; do not expose device identifiers |

## Design and contracts

### Data/API/state contract

`get_wellness_report(p_start_date, p_end_date, p_timezone)` accepts an
inclusive date window of 1–90 days and returns only the authenticated caller's
normalized daily aggregates, coverage flags, and the timezone actually used.
The Next.js DAL exposes a typed DTO rather than raw database rows.

`goals` stores one active goal per metric. Updating a goal keeps its creation
time; archiving sets it inactive with an end date, preserving the row for
history. Supported metrics are steps, active minutes, workouts, sleep duration,
and bedtime consistency.

### Data lifecycle

- Data created/read/updated/deleted: goals; report RPC reads normalized rows;
  profile timezone is updated through the existing profile table.
- Owner/user-scope key: `auth.uid()` / `user_id` with RLS.
- Provenance and audit metadata: goal timestamps; normalized rows retain
  existing import/provenance fields.
- Retention and cleanup: goals cascade on account deletion; no raw source data
  is added.
- Import/export/deletion behavior: existing import deletion remains canonical;
  report data disappears with canonical row deletion.

### Migration plan

- Migration name: `20260815100000_add_step6_goals_and_report_rpc.sql`.
- Expand only: add goals table, indexes, grants/RLS, and the read-only RPC.
- Clean reset and schema lint are required locally.
- Production is explicitly out of scope; rollback is application rollback plus
  leaving the additive table/function in place.

## Environment and secret delta

No variables, credentials, callbacks, domains, or provider settings change.

## Third-party integration delta

None. Supabase local/staging is used through existing project configuration;
there is no provider-console mutation in this slice.

## Security and privacy review

- [x] Authentication and authorization boundary identified.
- [x] Owner access and cross-user denial tests defined.
- [x] Input validation and 90-day query bound defined.
- [x] RLS and explicit grants reviewed.
- [x] No secret is browser-visible or added.
- [x] Raw health payloads, source names/paths, GPS, ECG, and tokens stay out of
  logs and UI contracts.
- [x] Non-clinical wording is used.

Threats/mitigations specific to this change:

- Cross-user report/goal access is blocked by `auth.uid()` predicates and RLS.
- Unbounded report scans are blocked by the inclusive 90-day RPC validation and
  existing owner/time indexes.
- Client-tampered Server Action fields are checked against the server catalog.

## Work packages

| ID | Deliverable | Dependencies | Verification | Status |
| --- | --- | --- | --- | --- |
| A | Goals schema, report RPC, grants/RLS | Steps 4–5 | reset, lint, focused RLS checks | complete |
| B | Server DAL, timezone/goal actions, typed contracts | A | typecheck, lint, build | complete |
| C | Summary, goals, dashboard, and reports UI | B | build and browser walkthrough | complete |
| D | Evidence and tracker handoff | A–C | privacy-safe interactive observation | complete |

## Test plan

| Layer/scenario | Fixture/data | Command or procedure | Expected result | Evidence location |
| --- | --- | --- | --- | --- |
| Unit/static | typed report/goal DTOs | `npm run typecheck`, `npm run lint`, `npm run build` | pass; lint clean | `apps/web` command output |
| Migration/RLS | existing sanitized pgTAP fixture plus Step 6 rows | `npx supabase db reset --local --yes`, `npx supabase db lint --local --fail-on error`, `npx supabase test db --local supabase/tests` | pass; 164 assertions; owner reads, other user sees zero, report range is bounded | local command output |
| Browser/E2E | synthetic local Auth account with no imported health data | `npx playwright test --config e2e/playwright.step6.config.mjs` | pass; summary → goals save → dashboard → reports works | `apps/web/test-results/browser/step6-summary-safe.png` |
| Failure/recovery | empty account state | authenticated browser walkthrough | safe empty-state copy and no raw errors | browser test output |

## Observability and support

- Safe fields: route, selected range, request outcome, row counts.
- Prohibited fields: email, source names/paths, raw values in logs, tokens, and
  provider credentials.
- User-facing query failures say the report could not load and offer retry.

## Rollout and rollback

- Feature enablement: routes are available only to authenticated users.
- Deployment order: migration, web build, then browser smoke.
- Rollback: revert web routes/actions; keep additive schema for forward repair.
- Stop condition: any cross-owner read, raw-data exposure, or unbounded query.

## Evidence and handoff

- Files/migrations/contracts changed: migration, typed DAL/actions, four routes,
  dashboard components, and focused browser fixture/config.
- Commands and results: web typecheck/lint/build, clean local Supabase reset,
  schema lint, 164 pgTAP assertions, and focused browser flow are green.
- Interactive evidence: local Playwright/Chromium walkthrough passed with a
  synthetic account and privacy-safe screenshot.
- Known limitation: hosted staging verification remains pending unless explicitly
  run; production remains excluded.

## Change history

| Date | Proposed delta | Impact | Decision/approver |
| --- | --- | --- | --- |
| 2026-08-15 | Initial Step 6 implementation plan | Defines one focused local/staging UX slice | User request |
| 2026-08-15 | Recorded local schema, web, and browser evidence | Implementation complete; user acceptance and PR review remain the release gate | Engineering handoff |
