# Change plan: Step 7 explainable scores, trends, and suggestions

## Metadata

- Change ID: 0007
- Milestone/work package: Step 7 — explainable scores, trends, deterministic suggestions, and safety copy
- Owner: engineering
- Status: implementation complete; product approval pending
- Baseline commit: 7412677
- Branch: codex/step-7-explainable-scoring
- Related issues: #42, #43, #44, #45
- Target environments: local / CI / preview or non-production staging
- Requested/last updated date: 2026-08-15

## Outcome

Add a small, deterministic score and goal-trend explanation to the existing
reports experience. The score is coverage-aware, versioned in the domain
output, and explicit about the 28-day window and evidence used.

This first slice uses the existing bounded report RPC and active goals. The
working defaults are intentionally centralized and easy to revise after the
Step 7 product approval: sleep target 8 hours, steps target 7,500/day, active
time target 22 minutes/day, three workouts/week, and seven covered days for
daily components.

## Non-goals

- Diagnosis, treatment, ECG/RRI interpretation, medical outcome prediction, or
  external AI/inference providers.
- New provider, secret, scheduler, background job, or health-data egress.
- Forecasting beyond a descriptive 28-day goal-completion trend.
- Replacing the existing report aggregation or adding a second analytics store.

## Scope

- Pure TypeScript score domain logic with fixed version, weights, coverage
  rules, deterministic recomputation, and safe suggestions.
- Reports UI showing total/component scores, coverage, evidence window, trend,
  insufficient-data states, and non-clinical safety copy.
- Focused unit fixtures for complete, missing-data, and trend-boundary cases.

## Acceptance for this slice

- Identical report/goals fixtures produce identical score, component, and trend
  output.
- Missing components are excluded and visibly reweighted; they never become a
  low score.
- Suggestions name the data window and evidence category without medical
  language.
- Reports retain their existing owner-scoped and bounded data contract.
- Local typecheck, lint, build, and focused scoring tests pass.

## Pending product gate

Issue #42 remains open for approval of thresholds, labels, and missing-data
semantics. The constants above are implementation defaults, not a claim that
the user gate has been accepted.

## Rollback

Remove the reports score section and scoring module; the existing Step 6 report
RPC and routes remain usable. No hosted resource or provider configuration is
changed by this slice.

## Evidence

- Focused score fixtures: 3 passing tests covering deterministic output,
  missing-component reweighting, and an improving trend boundary.
- Web: `npm run typecheck`, `npm run lint`, and `npm run build` passed.
- Database: clean local reset, schema lint, and 172 pgTAP assertions passed;
  owner read/insert and authenticated update/delete denial are covered.
- Browser: one synthetic-account Chromium flow passed summary → goals →
  dashboard → reports and asserted the score, insufficient-data, and trend
  states. Privacy-safe evidence: `apps/web/test-results/browser/step7-score-safe.png`.

## Remaining Step 7 work

- Product approval is still needed for the working thresholds, labels, and
  missing-data semantics in issue #42.
- The snapshot table is insert-only and owner-scoped; later recomputation or
  history browsing can build on it without changing the report contract.
