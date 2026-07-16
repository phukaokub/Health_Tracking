# ADR 0004: Restrict import metadata writes to reviewed RPCs

- Status: accepted
- Date: 2026-07-16
- Decision owners: repository maintainer with Codex implementation support
- Related milestone/change/PR: Step 3 / 3H / `codex/step-3-zip-cleanup`
- Supersedes / superseded by: supersedes ADR 0002 only for import RPC execution privileges

## Context

ADR 0002 correctly chose the foreground user's verified JWT plus the public Supabase publishable key so the browser and Go API never need an elevated provider secret. The initial security-invoker RPC implementation also granted authenticated users direct insert, update, and delete privileges on owner-scoped import tables. RLS prevented cross-user access, but an owner could still bypass the reviewed state transitions, directly delete metadata, and orphan private Storage objects.

## Decision drivers

- Preserve user-JWT authentication and cross-owner isolation without adding a service-role secret.
- Ensure all metadata mutation follows validation, idempotency, job, and Storage-first cleanup transitions.
- Keep direct owner reads available for RLS defense and diagnostics while applying least privilege to writes.
- Use fixed function signatures, explicit `auth.uid()` predicates, empty `search_path`, and narrow execute grants.

## Options considered

### Option A: Definer RPC writes with direct table writes revoked

- Benefits: removes the direct REST table mutation path while retaining the existing foreground user JWT and stable RPC/API contracts.
- Costs/risks: definer functions bypass table RLS, so every function must explicitly derive and enforce `auth.uid()` and must never interpolate object names or use a mutable search path.
- Environment/integration impact: expand-only migration; no new variable or credential.
- Security/privacy/data impact: callers can mutate only through reviewed owner-predicated functions; direct owner reads remain RLS-scoped.
- Reversibility: grants and function security mode can be changed in a forward migration if a narrower database role is introduced.

### Option B: Keep security-invoker functions and direct table writes

- Benefits: RLS remains automatically authoritative inside every statement.
- Costs/risks: any authenticated owner can bypass state transitions and Storage-first deletion through PostgREST table endpoints.
- Environment/integration impact: none.
- Security/privacy/data impact: creates orphan-object and job-integrity risks.
- Reversibility: not accepted.

## Decision

Revoke authenticated insert, update, and delete privileges from all import metadata tables and convert the seven public import RPCs to `SECURITY DEFINER`. Each RPC has a fixed signature, `search_path = ''`, derives the caller from `auth.uid()`, and predicates every existing-row read or mutation by that user ID. Execute remains revoked from public/anonymous roles and granted only to authenticated callers. Storage object operations continue to use the caller's JWT and owner-path RLS.

## Consequences

### Positive

- Owners cannot bypass Storage-first cleanup by deleting metadata directly.
- The Go API can keep forwarding the short-lived user JWT; no elevated runtime secret is introduced.
- Cross-owner behavior remains fail-closed and testable at the function and Storage layers.

### Negative and follow-up

- Every future import RPC requires explicit caller checks and a security review before execute is granted.
- System-wide scheduled cleanup still needs a separate least-privileged Step 4 worker identity decision.
- Table write policies remain defense documentation but are unreachable to authenticated callers without table privileges.

## Validation and revisit trigger

pgTAP must prove authenticated users have only direct SELECT grants, all seven RPCs are definer functions, anonymous execute is denied, direct owner deletion fails, cross-owner reads/deletes fail, and RPC create/delete flows still converge. Revisit if a dedicated non-bypass database role replaces definer functions or any RPC lacks an explicit `auth.uid()` predicate.
