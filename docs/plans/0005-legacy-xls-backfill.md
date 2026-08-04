# Change plan: Legacy XLS allowlisted historical backfill

## Metadata

- Change ID: 0005
- Milestone/work package: Step 5 - Legacy XLS allowlisted backfill
- Owner: repository maintainers
- Status: done; implementation and staging verification merged in PR #63
- Baseline commit: `57cae63`
- Branch: `codex/step5-legacy-xls-backfill`
- Related issue/PR/ADR: PR pending
- Target environments: local, CI, and non-production staging verification
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
- Hosted-provider configuration beyond the explicitly approved non-production
  staging verification, production mutation, or Step 3's deferred suite.

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

- BIFF8 is capped at 16 MiB, 128 sheets, 100,000 rows, 128 columns, and 100,000
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
- Per the repository verification standard, exercise the import in a real
  local browser/computer session or non-production staging and capture a
  screenshot of the safe count result or a redacted application-log excerpt.
- For the user gate, privately upload one actual Huawei BIFF8 `.xls` export
  through staging, record only inserted/conflicted/excluded (and any exposed
  ambiguous) counts, verify cleanup, and never commit or send the workbook.

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
- Documentation checks passed. A private actual Huawei BIFF8 `.xls` export was
  processed through non-production staging at `POST /api/v1/worker/trigger`
  using the server-only trigger gate. The redacted application log reported
  one file processed, zero normalized records, and warnings for excluded and
  unknown sheets. The owner-scoped quality result was inserted 0, conflicted
  0, excluded sheets 7, unknown sheets 67, ambiguous 0. The Storage object,
  import file/quality rows, Auth account, and local state were removed, with
  the import tombstone in `deleted` state; the trigger gate was restored to
  false. No workbook was sent or committed.
- PR #62 implementation CI passed, and PR #63 follow-up CI passed Documentation,
  API, Web, and Supabase schema/RLS/browser checks before squash merge as
  `fb292e2`.

## Change history

| Date | Proposed delta | Impact | Decision/approver |
| --- | --- | --- | --- |
| 2026-07-30 | First bounded Step 5 slice | Local/CI source, schema, API, UI | User requested implementation |
| 2026-07-30 | Add repository-wide interactive evidence and private actual-workbook staging gate | Adds local-browser/staging screenshot or redacted-log evidence; no production/provider configuration change | User requested verification standard; staging verification completed with redacted log evidence |
| 2026-07-30 | Actual-workbook compatibility repair and staging gate | Tightens BIFF8 SST preflight against OLE-container false positives and raises the bounded sheet cap to 128 for the observed Huawei export; private staging result is recorded above | Follow-up source change merged in PR #63; no production mutation |
| 2026-08-05 | Step 5 completion merge | Follow-up parser fix, verification-standard evidence, and private staging result merged in PR #63 | Step 5 complete for the approved local, CI, browser, and non-production staging scope |
