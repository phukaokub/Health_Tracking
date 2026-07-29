# ADR 0005: Background parser runtime and Supabase access

- Status: accepted and verified for the manual staging worker; production remains gated
- Date: 2026-07-17
- Decision owners: product/release owner and engineering/security owner
- Related milestone/change/PR: Step 4 / 4F-4H / `codex/step-4-plan`
- Supersedes / superseded by: none; extends ADR 0002 beyond foreground user sessions

## Context

Step 3 creates an owner-scoped queued import job using the user's short-lived JWT. Step 4 must continue after that browser session expires, read verified private Storage parts across users, write normalized owner rows, renew leases, and recover from worker termination. A broad Supabase secret/service key bypasses RLS and has unacceptable default blast radius. Hosted runtime limits also matter: the supplied export shape includes a roughly 70.8 MiB JSON file and about 330 MiB total data.

Current provider guidance must be rechecked before acceptance. As reviewed on 2026-07-17, Vercel Functions default to a 300-second ceiling, while hosted Supabase Edge Functions have 256 MiB memory, 150-second Free-plan wall-clock, and 2 seconds CPU per request. Neither runtime is accepted without a generated 72 MiB benchmark and checkpoint/retry proof.

## Decision drivers

- No browser JWT dependency and no secret in browser code.
- Least-privilege access to one actively leased import's objects and mutation RPCs.
- Streaming Go parser support, bounded memory/time, checkpoint-safe termination, and deterministic retry.
- Secret rotation, revocation, audit ownership, staging/production separation, and fail-closed missing configuration.
- No source bytes through the foreground Next.js/Go request path and no raw payload in logs.

## Options considered

### Option A: Dedicated Supabase Auth worker identity plus lease-scoped RLS/RPCs

- Benefits: uses short-lived JWTs and Storage RLS; a leaked worker password cannot automatically bypass RLS; worker actions can require an admin-managed `app_metadata` claim and active lease generation.
- Costs/risks: serverless invocations must acquire/refresh sessions without hitting Auth rate limits; Storage policy helpers are security-sensitive; the worker account must be blocked from normal web usage.
- Environment/integration impact: staging/production worker Auth accounts, encrypted identifier/password, publishable key, exact worker runtime and trigger secret.
- Security/privacy/data impact: narrowly scoped read/write paths are possible without a service-role key, but every helper and claim must be tested against forged/stale/cross-owner requests.
- Reversibility: worker adapter and policies can be replaced while parser/domain code remains pure.

### Option B: Supabase secret/service key in the worker

- Benefits: simplest Data/Storage access and no Auth session acquisition.
- Costs/risks: bypasses RLS and grants project-wide access; every owner/path check becomes application-only; compromise has the largest blast radius.
- Environment/integration impact: broad provider secret in every worker environment with rotation/incident burden.
- Security/privacy/data impact: unacceptable as the default for sensitive multi-user health data.
- Reversibility: technically easy, but migration away does not undo exposure risk.

### Option C: Dedicated non-bypass Postgres role plus separate Storage broker

- Benefits: narrow database grants and no Auth login rate dependency; broker can issue one-object access after lease validation.
- Costs/risks: two credential/control planes, connection pooling, a trusted broker with Storage secret access, more deployment and failure modes.
- Environment/integration impact: custom database role/password, broker function/runtime, trigger secret, provider configuration and rotation.
- Security/privacy/data impact: can be least privilege but is substantially more complex and still places a broad Storage credential in the broker.
- Reversibility: moderate; parser remains isolated, infrastructure does not.

### Option D: Supabase Edge Function performs parsing with provider secret

- Benefits: colocated with Storage/database, managed trigger/secret integration.
- Costs/risks: Deno/TypeScript rewrite, 256 MiB memory, 150-second Free wall clock, 2-second CPU request limit, and broad secret access; mismatched with the existing Go service.
- Environment/integration impact: Edge Function deployment, Cron/Queue setup, provider secrets.
- Security/privacy/data impact: provider-internal secret is still broad and function bugs bypass RLS.
- Reversibility: high rewrite cost.

## Decision

Prefer Option A for the staging spike: a dedicated non-browser Supabase Auth worker identity with admin-managed `app_metadata.import_worker = true`, short-lived access tokens, lease-generation checks, and no direct canonical table writes. The worker calls fixed-signature claim/renew/persist/complete/fail RPCs and may read only Storage parts belonging to its current valid lease. `PUBLIC`/`anon` execute is revoked; browser users cannot call worker RPCs successfully.

Run the Go worker in bounded invocations, initially targeting Vercel's 300-second runtime with a 240-second application deadline. Process and commit bounded batches/checkpoints so termination is safe. The trigger remains disabled until Auth session acquisition, runtime headroom, Storage policy, cross-owner denial, and secret rotation all pass in staging.

The product/release owner and engineering/security owner approved Option A on
2026-07-19 and authorized its staging provider configuration on 2026-07-30.
The dedicated Auth identity, encrypted Vercel variables, active-lease Storage
policy, fixed persistence RPCs, and a manual default-off trigger are now
verified in staging. No service-role key was introduced. Production identity,
trigger, scheduler, and provider configuration remain a separate Step 9 gate.

## Consequences

### Positive

- Parser code stays independent of provider credentials and can be tested locally.
- Worker compromise is constrained by claims, lease state, fixed RPCs, and Storage RLS rather than relying only on application filters.
- Runtime termination is recoverable through transaction-coupled checkpoints.

### Negative and follow-up

- Each manual invocation performs a worker Auth sign-in; a future scheduled
  cadence must remain within Auth limits or revisit this decision.
- Raw source parts have a 24-hour recovery window after a terminal worker
  result; cleanup is eligible only after that window and when no lease is active.
- Security-definer helpers that inspect worker claims/leases require empty search paths, explicit execute grants, pgTAP cross-owner tests, and Supabase advisor review.
- Staging Vercel runtime configuration is active on a separate staging project;
  production cost/runtime selection remains deferred.
- Recovery-expired raw-source cleanup reuses the accepted identity and has
  separate SELECT/DELETE policy checks; broader abandoned-upload scheduling is
  still outside this decision.

## Acceptance evidence

- Generated 72 MiB single-file and 330 MiB/five-file benchmarks completed with
  deterministic replay and more than 25% time/memory headroom; generated
  capacity tests used no provider source egress.
- A generated private-Storage job authenticated the worker, persisted scalar,
  sleep, activity, and workout rows, dropped ECG/RRI/GPS/route content, and
  returned only counts and stable warning codes.
- Active/stale lease, browser-shaped claim, anonymous execute, verified-file,
  batch replay, dedupe, and owner RLS tests pass locally; hosted grants and
  policies match those controls.
- Trigger rotation/redeployment succeeded, real processing stayed default-off
  outside the bounded drill, and a second invocation was idle.
- The approved 24-hour deadline was verified, then the synthetic test clock was
  advanced explicitly to exercise cleanup without a 24-hour wait. Raw source,
  canonical rows after owner delete, and the disposable test account all
  converged to zero.
- Supabase advisors report only reviewed authenticated definer notices,
  unrelated performance information, and the staging Auth leaked-password
  setting that remains a Step 8/production-readiness item; no missing RLS or
  anonymous worker-helper finding remains.

## Revisit triggers

Revisit on provider runtime/limit change, Auth rate-limit failure, benchmark headroom below 25%, need for concurrent workers, credential incident, Storage policy complexity that cannot be proven, or adoption of a dedicated long-running worker platform.
