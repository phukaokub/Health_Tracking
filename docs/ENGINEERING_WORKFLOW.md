# Engineering workflow

This is the software development lifecycle for Health Tracking. It is designed for a small team working with Codex while still preserving the controls needed for private health data, external providers, database migrations, and production releases.

## Operating principles

- Deliver thin, usable vertical slices across UI, API, database, security, tests, and operations.
- Treat configuration, provider-console changes, migrations, and runbooks as implementation work, not follow-up chores.
- Keep `main` releasable. Use short-lived `codex/<change-name>` or feature branches and merge through pull requests.
- Use synthetic or explicitly sanitized data outside production. Never copy production health data into local, CI, preview, or staging.
- Make every external side effect reversible or document why it is not. Database rollback normally means a forward repair, not destructive down-migration.
- A milestone is complete only when its code, configuration, tests, documentation, evidence, and user verification gate are complete.
- Plans are baselines, not promises carved in stone. Change them deliberately and retain the decision and impact trail.

## Work-item lifecycle

| Stage | Required output | Gate to continue |
| --- | --- | --- |
| 1. Intake | Problem, desired outcome, user value, constraints, and milestone link | Outcome is understandable without prescribing a solution |
| 2. Ready | A copy of [`templates/CHANGE_PLAN.md`](templates/CHANGE_PLAN.md) or equivalent issue content | Definition of Ready passes |
| 3. Design | Contracts, data model, threat/privacy review, environment and integration delta, test plan, rollout and rollback | Important decisions are accepted; unresolved items have owners |
| 4. Build | Small commits implementing independently testable work packages | Local checks pass for each affected layer |
| 5. Review | Pull request, CI, preview when useful, migration diff, and evidence | Review comments resolved and required checks green |
| 6. Verify | User flow, failure states, access isolation, and milestone acceptance demonstrated | User accepts the milestone gate or records requested changes |
| 7. Release | Completed release record, controlled promotion, smoke tests, and rollback readiness | Production verification is green and release evidence is saved |
| 8. Operate | Monitoring, incident response, follow-up work, and retrospective updates | Learning is reflected in plans, tests, or runbooks |

Documentation-only changes can use a shortened lifecycle, but still need a clear outcome, review, link/command validation, and a rollback of the documentation change if it is inaccurate.

## Definition of Ready

A change is ready to implement when all applicable items are known:

- the user-visible outcome and explicit non-goals;
- acceptance scenarios, including empty, loading, error, retry, and unauthorized states;
- affected web, API, database, Storage, Auth, job, and documentation components;
- migration and compatibility strategy;
- environments affected and configuration names required;
- third-party setup, callback URLs, permissions, quotas, cost, and owner;
- data classification, retention/deletion behavior, and logging restrictions;
- test layers and fixtures required;
- rollout, rollback, feature-disable, and cleanup approach;
- open decisions and who must approve them.

Unknown implementation details can remain, but an unknown that materially changes security, data retention, provider cost, or architecture blocks implementation until decided.

## Planning and change control

### Decompose work at three levels

1. A milestone in [`IMPLEMENTATION_STEPS.md`](IMPLEMENTATION_STEPS.md) describes an outcome and exit gate.
2. Work packages in [`DELIVERY_TRACKER.md`](DELIVERY_TRACKER.md) describe reviewable vertical slices and dependencies.
3. A change plan describes exact tasks, contracts, tests, environment changes, integration work, and rollback for one branch or pull request.

Default to one accepted milestone slice, one branch, and one pull request. Split a
slice only when the user requests it or when the change plan records an
independent compatibility, release, or review boundary.

Prefer a work package that can be merged and verified independently. If a package cannot be released safely on its own, identify the compatibility layer or feature flag that keeps `main` releasable.

### Adjust an accepted plan

When new information changes the baseline:

1. Record the proposed delta in the delivery tracker or active change plan.
2. Evaluate impact on scope, architecture, data, privacy, migrations, environments, integrations, tests, schedule, cost, and rollback.
3. Mark the change as `proposed`, `accepted`, or `rejected`; never silently replace an accepted requirement.
4. Obtain user approval when the change affects product behavior, safety boundaries, production cost, provider choice, or release timing.
5. Update the project plan or milestone only if the long-lived baseline changed.
6. Create an ADR when the decision is architectural, expensive to reverse, or likely to be questioned later.

Small implementation discoveries that stay inside accepted scope can be recorded in the pull request without a separate approval.

### Status vocabulary

- `planned`: accepted but not started.
- `ready`: dependencies and Definition of Ready are satisfied.
- `in progress`: implementation is active.
- `in review`: a pull request or user verification is active.
- `blocked`: no safe progress is possible without a named decision or external action.
- `accepted`: the user verification gate passed, but merge or release may still be pending.
- `done`: merged, required environments updated, evidence recorded, and no required work remains.
- `deferred`: intentionally removed from the current release with a recorded reason.

## Branch, commit, and pull-request workflow

1. Start from the latest protected `main` unless the active task is explicitly continuing an existing branch.
2. Create a short-lived branch named `codex/<concise-change-name>` by default.
3. Link the branch to a milestone and change plan in the delivery tracker.
4. Commit coherent changes with an imperative message such as `feat: add import manifest schema` or `docs: define release workflow`.
5. Rebase or merge `main` only when needed; do not rewrite shared history without agreement.
6. Open a pull request using [`.github/pull_request_template.md`](../.github/pull_request_template.md).
7. Require unique, green CI checks before merge. Protect `main` from force-push and deletion. Enable required reviews and deployment protection where the GitHub plan supports them.
8. Use squash merge for a noisy work branch or preserve multiple commits when they form useful review and rollback units.
9. Delete the remote branch after merge unless it is intentionally long-lived.

No pull request may claim an integration or production environment is configured based only on source-code support. Provider-side configuration and a verification result are separate acceptance items.

## Implementation controls

### Web and API contracts

- Define the OpenAPI or request/response contract before connecting UI and API behavior.
- Keep the browser API base URL and Supabase publishable configuration public by design; never place a secret in a `NEXT_PUBLIC_*` variable.
- Return structured errors with request IDs. User messages must be actionable without revealing sensitive internals.
- Preserve backward compatibility during a rolling release. Add fields before requiring them; stop readers before removing fields.

### Database, RLS, and Storage

- Put every schema and policy change in a timestamped migration. Do not make untracked production edits in the dashboard.
- Prefer expand/migrate/contract across separate releases for destructive or large changes.
- Enable RLS on exposed application and Storage data, grant only required roles, and test both owner access and cross-user denial.
- Use stable, owner-scoped Storage paths. Test create, read, update/upsert, and delete separately because policies can differ by operation.
- Run migrations locally from a clean reset and then in staging before production.
- Never use production health data as a fixture. Fixtures must be generated or explicitly sanitized and reviewed.

### Third-party integrations

Every provider change must update [`THIRD_PARTY_INTEGRATIONS.md`](THIRD_PARTY_INTEGRATIONS.md) and include:

- purpose, owner, account/project, environments, and current status;
- data sent or received, permissions/scopes, retention, and privacy impact;
- credentials and secret-store location by name only;
- exact callback/origin/domain configuration;
- quotas, rate limits, cost trigger, and expected failure behavior;
- local/staging verification, production smoke test, rollback, and offboarding steps.

Use separate provider credentials or projects for local/staging and production where supported. A provider secret copied into chat, logs, an issue, or Git must be treated as exposed and rotated.

### Environment and secret changes

- Update [`ENVIRONMENTS_AND_SECRETS.md`](ENVIRONMENTS_AND_SECRETS.md) and the relevant `.env.example` in the same pull request as code that consumes a new variable.
- Record classification (`public`, `internal`, `secret`, or `sensitive data`), consumer, owner, required environments, and rotation trigger.
- Add values directly to the approved local, Vercel, Supabase, or GitHub store. Do not put values in the pull request, screenshots, terminal transcripts, or documentation.
- Verify a new deployment after any Vercel environment-variable change; existing deployments do not receive the new value.
- Prefer provider integrations and short-lived credentials over permanent CI tokens where possible.

## Verification strategy

The change plan selects checks from this matrix. Commands are run from the owning application directory unless shown otherwise.

| Change type | Minimum local evidence | Additional gate |
| --- | --- | --- |
| Documentation/config metadata | Links and commands checked; no values or stale names | Reviewer confirms consistency across docs/templates |
| Web UI or server action | `npm run lint`, `npm run typecheck`, relevant tests, `npm run build` | Browser walkthrough or E2E for the affected flow |
| Go API/domain | `gofmt`, `go vet ./...`, `go test ./...` | Contract and unauthorized/error-path tests |
| Supabase schema/RLS | `npx supabase db reset`, `npx supabase db lint --local --fail-on error`, policy tests | Apply to staging and test cross-user denial |
| Auth/provider | Email/password and OAuth happy path, callback failure, sign-out, expired/invalid token | Local Mailpit plus hosted staging provider test |
| Upload/import | Unit tests, synthetic large fixture, retry/resume/cancel, checksum mismatch | Browser-to-Storage-to-job E2E in staging |
| Parser/normalization | Sanitized fixtures, malformed input, dedupe, deterministic output | Coverage/provenance review; no raw payload retained |
| Production release | Full CI, staging smoke, migration review, release record | Production smoke, monitoring check, rollback target recorded |

The current CI workflow enforces local-document links/credential-pattern checks, web lint/typecheck/build, Go format/vet/test, and local Supabase migration/lint/pgTAP checks. Do not describe parser, browser E2E, dependency/vulnerability, or repository-wide secret-scan gates as active until their workflows actually exist. Add those gates incrementally with the milestone that needs them, then enforce them before production in Step 8.

## Review and evidence

A pull request should make review possible without reconstructing the work from chat. Attach or link:

- the accepted outcome and change plan;
- affected contracts, migrations, integration/configuration delta, and screenshots when useful;
- commands run and concise pass/fail results;
- security/privacy impact and explicit cross-user denial evidence when relevant;
- known limitations, deferred work, and an issue/tracker entry for each required follow-up;
- rollout, rollback, and feature-disable instructions;
- exact provider-side checks completed, without credential values.

CI output is evidence, not the only evidence. User-visible flows and provider-console configuration need direct verification.

## Definition of Done

A change is done only when all applicable statements are true:

- acceptance scenarios pass, including failure and unauthorized paths;
- code is formatted, tested, reviewed, and merged;
- migrations are reproducible from a clean local reset and verified in the target non-production environment;
- environment examples, secret inventory metadata, and integration records are current;
- privacy, retention, deletion, and logging behavior match the plan;
- operational diagnostics identify failures without exposing health data or credentials;
- release and rollback steps are executable;
- evidence and current status are recorded in the delivery tracker;
- the user verification gate is accepted when the milestone requires it;
- no unowned blocker or required follow-up is hidden behind the word "complete."

## Release, hotfix, and incident paths

Standard production releases follow [`RELEASE_RUNBOOK.md`](RELEASE_RUNBOOK.md).

For a hotfix:

1. Record the incident symptom, affected environment, and containment action.
2. Branch from the production commit, minimize scope, and preserve the same security and test gates that are safe under the circumstances.
3. Obtain release approval, deploy, smoke-test, and monitor.
4. Merge the fix back to `main` and update tests/runbooks so the failure is less likely to recur.

For a suspected secret or sensitive-data exposure:

1. Stop further disclosure and remove public access where possible without destroying evidence.
2. Revoke or rotate the credential in its source system; updating only a local file is insufficient.
3. Redeploy all consumers and invalidate affected sessions or tokens when applicable.
4. Review provider and application audit logs using a private incident record.
5. Check Git history, build logs, artifacts, screenshots, and chat/issue content for additional exposure.
6. Record preventive changes without committing the leaked value or private incident evidence.

## Milestone handoff

Every milestone handoff is self-contained and reports:

1. milestone and status (`accepted` is distinct from `done`);
2. outcome demonstrated and acceptance scenarios;
3. files, migrations, contracts, environments, and integrations changed;
4. commands and test evidence;
5. security, privacy, data-retention, and logging impact;
6. rollout, rollback, and unresolved risks;
7. decisions made, deviations from baseline, and deferred work;
8. the next exact approval or action required.
