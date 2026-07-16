# ADR 0002: Preserve user RLS for foreground import persistence

- Status: accepted
- Date: 2026-07-16
- Decision owners: product owner and engineering
- Related milestone/change/PR: Step 3 work package 3F; DEC-007
- Supersedes / superseded by: none

## Context

The Go API must persist import metadata and reconcile private Storage objects for an authenticated browser session. Source bytes must never pass through the Go API. The implementation needs an owner boundary without introducing a broad Supabase secret before a background-worker access model is designed for Step 4.

## Decision drivers

- Keep Postgres and Storage RLS authoritative for foreground user requests.
- Do not introduce or expose a service-role or Supabase secret key.
- Keep all source bytes on the browser-to-Storage path.
- Make create, completion, and job creation idempotent and transactional.
- Keep the future asynchronous worker credential as a separate, explicit decision.

## Options considered

### Option A: Forward the verified user JWT with the publishable key

- Benefits: preserves owner RLS, has no elevated credential, and works with the Data and Storage APIs.
- Costs/risks: the user JWT expires; operations must remain user-driven; application validation must also be enforced by database constraints or invoker functions because authenticated users can reach granted Data API objects directly.
- Environment/integration impact: add `SUPABASE_PUBLISHABLE_KEY` to the Go runtime as a public project identifier.
- Security/privacy/data impact: cross-user access remains denied by RLS; no source bytes enter Go.
- Reversibility: the repository adapter can later move to a dedicated non-bypass database role.

### Option B: Dedicated non-bypass Postgres role

- Benefits: supports a trusted server transaction boundary and narrower direct Data API grants.
- Costs/risks: adds a database secret, pooling/connection concerns, and careful request-claim setup.
- Environment/integration impact: requires per-environment database credentials and rotation.
- Security/privacy/data impact: safe only if the role cannot bypass RLS and claims are established correctly.
- Reversibility: moderate; repository interfaces can isolate the change.

### Option C: Supabase secret/service credential

- Benefits: straightforward server access.
- Costs/risks: bypasses RLS and creates the largest credential blast radius.
- Environment/integration impact: requires secret inventory, rotation, and incident handling.
- Security/privacy/data impact: every operation would depend on perfect application owner filters.
- Reversibility: technically easy but security risk is unacceptable for this milestone.

## Decision

Use Option A for Step 3 foreground import operations. The Go API forwards the bearer token it has already verified plus `SUPABASE_PUBLISHABLE_KEY`. Database mutations use explicitly granted, `SECURITY INVOKER` functions and owner-scoped RLS. Storage upload and deletion use the Storage API with the same user token. No service-role or Supabase secret key is introduced.

This decision does not authorize the Step 4 asynchronous worker. Its least-privileged database and Storage credential, owner checks, rotation, and incident procedure require a new ADR before parser execution.

## Consequences

### Positive

- Foreground requests retain database-enforced owner isolation.
- The browser receives only the normal publishable key and its own session token.
- Create/completion retries can converge without duplicate import jobs.
- The API remains metadata-only.

### Negative and follow-up

- User-driven operations fail after token expiry and must refresh/retry through the browser session.
- Direct authenticated Data API callers remain constrained by RLS and database validation, not by the Go route alone.
- Step 4 needs a separate background-access decision before any worker is enabled.

## Validation and revisit trigger

Validate with local owner/cross-owner database tests, API tests for missing/tampered JWTs and idempotency, and real Storage upload/delete probes using two users. Revisit if foreground calls need to continue after user-session expiry, if direct Data API exposure cannot be constrained adequately, or before Step 4 worker deployment.
