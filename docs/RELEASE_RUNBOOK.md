# Release runbook

This runbook defines the target path from an accepted change to production. Production deployment is not yet enabled; Step 9 must provision and verify the controls below before the first launch. Until then, local acceptance or a green pull request is not a production release.

Create one release record from [`templates/RELEASE_RECORD.md`](templates/RELEASE_RECORD.md) for every production release or hotfix.

## Release models

| Type | Use | Required approval |
| --- | --- | --- |
| Standard | Normal feature, fix, configuration, or migration release | User/release owner after staging evidence |
| Hotfix | Restore a broken or unsafe production path with minimal scope | User/release owner; abbreviated staging only when delay is riskier, with reason recorded |
| Documentation-only | No runtime/config/provider change | Normal pull-request review; no production smoke unless deployment is triggered |

Do not perform an untracked migration-only or provider-console-only release. Configuration and console changes need the same release record and verification as code.

## Target deployment model

- GitHub `main` is protected and is the only production source branch.
- Vercel has separate web and API projects and separate Preview/Staging and Production configuration.
- Supabase has separate staging and production projects.
- Production Vercel builds are staged from the same commit before domains are assigned, or an equivalent protected workflow ensures migrations complete before traffic moves.
- Database changes are backward-compatible. The default sequence is expand migration, API promotion, web promotion, verification, later contract cleanup.
- Supabase migrations are deployed by an automated GitHub/Supabase path. Do not make routine production schema changes manually from a workstation.
- A Vercel rollback changes application traffic only. It does not undo Supabase schema/data or restore previous environment variables.

If the implemented platform workflow differs, record the accepted model in an ADR and update this runbook before launch.

## Pre-release gate

The release owner confirms:

- [ ] Release record identifies version/name, commit SHA, pull requests, owner, window, and environments.
- [ ] Milestone/change acceptance is complete and the delivery tracker is current.
- [ ] Required CI checks are green for the exact commit.
- [ ] Web and API builds use locked dependencies; relevant migration, parser, contract, E2E, security, and secret scans pass.
- [ ] Environment-variable diff is reviewed by name and scope; no values appear in the pull request or record.
- [ ] Integration changes include provider-side setup, quota/cost review, failure behavior, and rollback.
- [ ] Migrations are reviewed, backward-compatible, reproducible from a clean local reset, and tested in staging.
- [ ] RLS and Storage policies include positive owner tests and negative cross-user tests.
- [ ] Data backfill/cleanup is idempotent, observable, bounded, and separately stoppable.
- [ ] Privacy, retention, deletion, and logging changes are accepted.
- [ ] Known limitations and deferred work are owned and do not violate release acceptance.
- [ ] A known-good application deployment and database recovery approach are identified.
- [ ] Production provider status, quota headroom, support access, and on-call/release contact are known.

Stop the release if any required item is unknown. Do not convert a failed gate into a post-release task without explicit risk acceptance.

## Stage and verify

### 1. Identify the candidate

Record the immutable commit SHA. Web, API, migrations, and release evidence must all refer to this SHA.

### 2. Reproduce baseline checks

From `apps/web`:

Run the candidate web server separately, or set `E2E_WEB_URL` to the intended target, before the E2E command.

```text
npm ci
npm run lint
npm run typecheck
npm run build
npm run test:e2e
```

From `services/api`:

```text
gofmt -l .
go vet ./...
go test ./...
```

From the repository root when migrations exist:

```text
npx supabase --help
npx supabase db reset
npx supabase db lint --local --fail-on error
```

Only list scripts that exist at release time. If a planned gate is not implemented, the first production release is blocked until it is either implemented or explicitly replaced by an accepted control.

### 3. Audit target configuration

- Compare configured variable names across web/API Preview or Staging and Production.
- Confirm every value points to the correct environment without printing the value.
- Confirm Auth Site URL, redirect allowlist, Google origins/callback, SMTP sender, API URL, and web URL align.
- Confirm no preview points to production Supabase and no production project uses local/test provider credentials.
- Redeploy after an environment-variable change; old Vercel deployments keep their old configuration.

### 4. Apply to staging

1. Apply migrations to the dedicated staging Supabase project through the approved automation.
2. Verify migration history, required grants, RLS, Storage policy, functions/triggers, and schema health.
3. Run any idempotent backfill with progress/error reporting.
4. Deploy the candidate web and API artifacts to the stable staging target.
5. Confirm both deployments report the candidate SHA/release identifier.
6. Seed or select synthetic test data only.

### 5. Run staging smoke and acceptance

| Area | Required check |
| --- | --- |
| Public web | Landing page loads over HTTPS with no console/server error |
| Email Auth | Sign-up, captured/delivered confirmation, sign-in, invalid password, reset, and sign-out |
| Google Auth | Consent, hosted Supabase callback, app PKCE callback, session, denial/failure state |
| API | Public health endpoint, valid user JWT, missing/invalid/expired JWT rejection, request ID |
| Authorization | User A cannot read/write User B profile, rows, imports, or Storage paths |
| Import | Synthetic fixture scans, uploads in bounded parts, resumes, creates one job, and handles checksum/failure |
| Data lifecycle | Import delete and account/data delete behavior for a test user when implemented |
| Diagnostics | Request/release/import IDs visible; no token, email, health value, GPS, or source content in logs |
| Resilience | Provider/API unavailable state is safe and retryable; duplicate submission is idempotent |

Attach non-sensitive results to the release record. User-visible changes need explicit acceptance before production approval.

## Promote to production

1. Announce/record the release window and freeze the candidate SHA.
2. Recheck provider status and the known-good rollback target.
3. Confirm backup/restore posture and migration stop conditions.
4. Stage production web and API builds from the candidate SHA without assigning production traffic, where configured.
5. Apply the reviewed expand migration to production through the protected migration job.
6. Verify migration history, schema health, grants, RLS, and critical read/write probes that do not expose user data.
7. Run bounded backfill only if approved; monitor separately and keep it stoppable.
8. Promote the API deployment, then the web deployment. Compatibility design must keep the old web/API valid during the transition.
9. Verify domains, TLS, environment identity, release SHA, Auth callbacks, API health, and logs.
10. Run the minimum production smoke suite with a dedicated test account and synthetic data. Never inspect another user's real health data for a smoke test.
11. Monitor error rate, latency, Auth failures, job failures, Storage errors, and provider quota/health for the recorded observation window.
12. Mark the release `successful`, `rolled back`, or `partially rolled back`; update the delivery tracker and open follow-up work.

## Rollback and containment

Choose containment based on the failing layer.

| Failure | First containment | Recovery |
| --- | --- | --- |
| Web-only regression | Roll web traffic to the known-good Vercel deployment | Fix forward and redeploy; verify current API compatibility |
| API regression | Disable affected feature/import worker; roll API traffic back | Fix forward; confirm new schema remains compatible with old API |
| Bad environment variable | Restore correct value in target scope and create a new deployment | Verify Auth/API/provider flow; environment rollback alone does not modify an old build |
| OAuth/SMTP provider issue | Disable affected provider/path if safe; keep alternate sign-in path | Restore/rotate provider config and test callbacks/delivery |
| Migration failure before completion | Stop promotion and backfill; leave current app serving if compatible | Repair with a reviewed forward migration |
| Migration succeeded but app fails | Roll application back only if old app supports expanded schema | Fix forward; do not destructively remove new columns during incident response |
| Incorrect backfill | Stop worker/job and disable dependent feature | Reconcile from provenance/audit data with a tested repair job |
| Suspected credential exposure | Revoke/rotate immediately and disable affected integration if needed | Redeploy every consumer, invalidate sessions where applicable, private audit |
| Suspected data isolation/exposure | Disable affected endpoint/import flow and preserve private evidence | Security incident process, policy fix, access review, user/legal response decision |

Never run an unreviewed destructive down migration against production. If rollback requires restoring a database backup, treat it as an incident: define recovery point/time impact, stop writes as needed, obtain explicit approval, and verify consistency after restore.

## Hotfix path

1. Confirm severity and containment; link a private incident record if sensitive.
2. Branch from the production commit and keep scope minimal.
3. Add a regression test where feasible.
4. Run all safe affected-layer checks and a focused staging smoke.
5. Obtain production approval and follow the promotion/rollback steps above.
6. Merge the hotfix back to `main`.
7. Complete a retrospective and update tests, monitoring, workflow, or documentation.

Urgency can shorten observation time; it does not authorize exposing secrets, bypassing user isolation, or making untracked database changes.

## Release completion evidence

A completed release record contains:

- candidate SHA and deployed web/API identifiers;
- migration versions and backfill/job identifiers;
- configuration and integration names changed, with no values;
- CI, staging, approval, production smoke, and monitoring evidence;
- known-good rollback deployment and database recovery posture;
- start/end time, owner, final status, incident/follow-up links;
- confirmation that logs and evidence contain no sensitive health or credential data.
