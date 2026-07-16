# Change plan: <concise outcome>

Copy this template for a non-trivial work package. Keep it beside the relevant docs or in the issue/pull request; do not put secret values or sensitive user data in it.

## Metadata

- Change ID:
- Milestone/work package:
- Owner:
- Status: proposed / ready / in progress / in review / accepted / done / deferred
- Baseline commit:
- Branch:
- Related issue/PR/ADR:
- Target environments: local / CI / preview / staging / production
- Requested/last updated date:

## Outcome

Describe the user or operational result in plain language.

### Success measures

-

### Non-goals

-

## User and failure flows

Describe the happy path and applicable empty, loading, unauthorized, invalid-input, provider-down, timeout, retry, cancel, partial-success, and deletion paths.

### Acceptance scenarios

1. Given ... when ... then ...
2. Given ... when ... then ...

## Scope and impact matrix

| Area | Change? | Detail / owning work package |
| --- | --- | --- |
| Next.js UI/routes/server actions | Yes/No | |
| Go API/domain/repository | Yes/No | |
| OpenAPI/client contract | Yes/No | |
| Postgres schema/index/grant/RLS | Yes/No | |
| Supabase Auth/JWT | Yes/No | |
| Supabase Storage/policies | Yes/No | |
| Background jobs/cron | Yes/No | |
| Third-party provider console | Yes/No | |
| Environment variables/secrets | Yes/No | |
| Logging/metrics/alerts | Yes/No | |
| Privacy/retention/deletion | Yes/No | |
| Documentation/support | Yes/No | |

## Dependencies and decisions

| Item | Type | Owner | Needed by | State / default |
| --- | --- | --- | --- | --- |
| | dependency/decision | | | |

Identify any assumption that would materially change architecture, security, data handling, cost, or product behavior. Create an ADR when expensive to reverse.

## Design and contracts

### Data/API/state contract

Include request/response examples, state transitions, idempotency keys, size/time limits, compatibility expectations, and stable error codes. Link large artifacts rather than duplicating them.

### Data lifecycle

- Data created/read/updated/deleted:
- Owner/user-scope key:
- Provenance and audit metadata:
- Retention and cleanup:
- Import/export/deletion behavior:
- Backfill/reconciliation:

### Migration plan

- Migration name(s):
- Expand/migrate/contract sequence:
- Lock/load expectation:
- Clean reset evidence:
- Staging verification:
- Production stop condition:
- Forward repair/rollback:

## Environment and secret delta

Never write values.

| Variable/credential name | Class | Consumer | Local | Preview/staging | Production | Store/owner | Rotation trigger |
| --- | --- | --- | --- | --- | --- | --- | --- |
| | public/internal/secret | | | | | | |

- Callback/origin/domain changes:
- `.env.example` and inventory updates:
- Redeploy/restart required:
- How missing/mis-scoped configuration fails safely:

## Third-party integration delta

- Provider/project and purpose:
- Data/scopes/permissions:
- Provider-side steps:
- Account, technical, billing, and recovery owner:
- Quota/rate limit/cost trigger:
- Privacy/region/retention consideration:
- Local/staging verification:
- Outage/timeout/retry behavior:
- Rollback/offboarding/revocation:
- Integration-register update:

## Security and privacy review

- [ ] Authentication and authorization boundary identified.
- [ ] Owner access and cross-user denial tests defined.
- [ ] Input/file/path/URL validation and size/rate limits defined.
- [ ] CSRF/origin/redirect/open-redirect behavior reviewed where applicable.
- [ ] RLS, explicit grants, and Storage operation policies reviewed.
- [ ] No secret is browser-visible, logged, committed, or copied into evidence.
- [ ] Health, email, GPS, ECG, source-file, and token logging is prohibited or redacted.
- [ ] Retention, cancellation, cleanup, import deletion, and account deletion behavior defined.
- [ ] Abuse, duplicate request, replay, retry, and idempotency behavior defined.
- [ ] Non-clinical wording and product safety boundary reviewed.

Threats/mitigations specific to this change:

-

## Work packages

| ID | Deliverable | Dependencies | Verification | Status |
| --- | --- | --- | --- | --- |
| A | | | | planned |

Each package should be reviewable and keep `main` safe. State how partially delivered work remains disabled or backward-compatible.

## Test plan

| Layer/scenario | Fixture/data | Command or procedure | Expected result | Evidence location |
| --- | --- | --- | --- | --- |
| Unit | | | | |
| API/contract | | | | |
| Migration/RLS/Storage | | | | |
| Browser/E2E | | | | |
| Provider/staging | | | | |
| Failure/recovery | | | | |

Include performance/memory/load checks when size or concurrency matters. Use generated or explicitly sanitized fixtures only.

## Observability and support

- Request/release/import/job identifiers:
- Safe structured fields:
- Prohibited fields:
- Metrics/alerts and thresholds:
- User-facing error/retry guidance:
- Diagnostic procedure:

## Rollout and rollback

- Feature enablement/disable mechanism:
- Deployment order:
- Migration/backfill order:
- Staging smoke:
- Production smoke:
- Observation window:
- Known-good rollback target:
- Database/provider/config containment:
- Stop conditions:

## Evidence and handoff

- Files/migrations/contracts changed:
- Commands and results:
- Screenshots/walkthrough:
- Provider-side verification (no values):
- Privacy/security result:
- Known limitations/deferred work:
- Deviations from accepted plan:
- Exact approval requested:

## Change history

| Date | Proposed delta | Impact | Decision/approver |
| --- | --- | --- | --- |
| | | | |
