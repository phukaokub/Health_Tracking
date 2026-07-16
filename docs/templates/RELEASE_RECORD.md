# Release record: <version or date>

Do not include secrets, health values, user emails, raw logs, or private incident evidence.

## Identity

- Status: planned / staging / approved / deploying / successful / rolled back / partial
- Release owner:
- Approver:
- Candidate commit SHA:
- Pull requests/change plans/ADRs:
- Web deployment ID/URL:
- API deployment ID/URL:
- Supabase migration versions:
- Release window and observation window:

## Scope

- User-visible changes:
- Operational/configuration changes:
- Environment-variable names/scopes changed (no values):
- Third-party/provider changes:
- Data migration/backfill/cleanup:
- Explicit non-goals/deferred work:

## Preflight

- [ ] Required CI checks green for candidate SHA.
- [ ] Dependencies locked and builds reproducible.
- [ ] Migration/RLS/Storage tests green.
- [ ] Environment and integration diff reviewed.
- [ ] Security/privacy/logging/deletion impact accepted.
- [ ] Staging smoke and user acceptance complete.
- [ ] Provider health/quota/cost headroom reviewed.
- [ ] Known-good app rollback and database recovery posture recorded.
- [ ] Release/incident contacts available.

## Evidence

| Gate | Evidence link/summary | Result | Owner/time |
| --- | --- | --- | --- |
| CI | | | |
| Staging migration | | | |
| Staging smoke | | | |
| User acceptance | | | |
| Production migration | | | |
| Production smoke | | | |
| Observation/alerts | | | |

## Promotion log

| Time | Action | Target | Result / deployment or job ID |
| --- | --- | --- | --- |
| | | | |

## Smoke results

- Public web/TLS:
- Email Auth:
- Google Auth:
- API/JWT:
- Cross-user denial:
- Import/job path:
- Deletion/cleanup:
- Logs/monitoring/redaction:

## Rollback

- Known-good web deployment:
- Known-good API deployment:
- Schema compatibility with rollback:
- Backfill stop/repair:
- Provider/config containment:
- Rollback trigger and decision owner:
- Rollback actions/results if used:

## Completion

- Final status:
- Start/end time:
- Incidents or user impact:
- Follow-up work and owners:
- Delivery tracker updated:
- Confirmation evidence contains no secrets or sensitive health data:
