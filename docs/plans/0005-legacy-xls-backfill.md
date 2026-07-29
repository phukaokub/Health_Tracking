# Change plan: Legacy XLS allowlisted historical backfill

## Metadata

- Change ID: 0005
- Milestone/work package: Step 5 - Legacy XLS allowlisted backfill
- Owner: repository maintainers
- Status: in review
- Baseline commit: `57cae63`
- Branch: `codex/step5-legacy-xls-backfill`
- Related issue/PR/ADR: PR pending
- Target environments: local and CI
- Requested/last updated date: 2026-07-30

## Outcome

Selected legacy BIFF8 `.xls` daily summaries fill historical gaps in the
owner's canonical samples. Granular Huawei JSON always wins an overlapping
metric/day conflict, and the UI exposes only safe counts and warning codes.

### Success measures

- Exact allowlisted sheets and headers produce canonical daily samples.
- Duplicate input is idempotent; JSON wins regardless of import order.
- Excluded/unknown sheets, ambiguous cells, ECG/RRI, GPS, and routes never persist.
- Owner-scoped quality counts show inserted, conflicted, excluded, and ambiguous totals.

### Non-goals

- `.xlsx`, dashboard analysis, clinical suggestions, ECG/RRI, GPS/routes.
- Hosted-provider configuration, production mutation, or Step 3's deferred suite.

## Design and contracts

The exact sheet names are `Daily Health Statistics`,
`Daily Sport Statistics`, `Sport Dimensions`, `Health Reports`, and
`Trend Reports`. Approved headers map date, steps, calories, distance, active
minutes, floors, resting heart rate, and average heart rate to existing
canonical scalar samples. Dates use the import's IANA timezone.

The deterministic identity is SHA-256 over contract version, source family,
metric type, local date, timezone, and canonical unit. It excludes values and
file/import IDs so duplicate or conflicting legacy rows converge on one daily
metric identity. The database suppresses legacy rows when overlapping
JSON exists and removes lower-priority legacy rows if JSON arrives later.

The owner API adds `normalization.legacy_backfill` containing counts only.
No sheet content, cell value, filename, path, email, or source byte is returned
or logged.

## Security, privacy, and dependency review

- BIFF8 is capped at 16 MiB, 64 sheets, 100,000 rows, 128 columns, and 100,000
  shared strings; malformed input and panics become stable safe codes.
- The fixture is generated from synthetic dates/values and scanned for
  identity, credential, ECG/RRI, GPS, and route markers.
- The quality table uses owner-only RLS SELECT; clients cannot write it.
- Import/account deletion cascades through owner/file foreign keys.
- `github.com/nkiri/xls` is pinned to `v0.0.4`. Offboarding replaces the
  isolated adapter while retaining the normalized contract and fixture tests.

## Test plan and acceptance

- Go: fixture mapping, timezone boundary, deterministic dedupe, malformed
  workbook/timezone, limits, privacy, worker dispatch, and bounded memory.
- Web: `.xls` included, `.xlsx` excluded, safe quality API/UI contract.
- pgTAP: schema/RLS/grants, worker RPC, count invariants, canonical day,
  JSON-wins precedence, deletion cascade, and owner isolation.
- Run the full affected local matrix once, then one PR and required CI.

## Rollout and rollback

The migration is expand-only. The parser runs only for `legacy-xls`. Removing
that classification disables new backfills. Production and hosted-provider
mutation remain excluded.

## Evidence

- Synthetic fixture: 10 canonical metrics across 2 dates; one excluded and one
  unknown sheet; deterministic Asia/Bangkok boundary verified.
- Parser benchmark: 5,632-byte BIFF8 fixture at about 0.17 ms/op and 114 KiB/op
  on the local verification host.
- Go: `go vet ./...` and `go test ./...` passed.
- Web: lint, typecheck, 21 unit tests, production build, and 2 browser import
  acceptance tests passed.
- Database: clean local reset and all 148 pgTAP assertions passed; schema lint
  reported no errors.
- Documentation checks passed. No hosted or production resource was changed.

## Change history

| Date | Proposed delta | Impact | Decision/approver |
| --- | --- | --- | --- |
| 2026-07-30 | First bounded Step 5 slice | Local/CI source, schema, API, UI | User requested implementation |
