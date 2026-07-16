# Environments and secrets

This document is the authoritative inventory for runtime environments, configuration names, secret locations, and credential lifecycle. It records metadata only. Never place an actual credential value here.

## Environment topology

```text
developer workstation
  -> local Supabase + local web/API
  -> pull-request CI and optional Vercel preview
  -> stable staging environment
  -> approved production release
```

| Environment | Purpose | Web/API target | Supabase target | Allowed data | Trigger and approval |
| --- | --- | --- | --- | --- | --- |
| Local | Development and destructive testing | `localhost:3000` / `localhost:8080` | Docker-based local stack | Generated fixtures and explicitly sanitized samples only | Manual; no approval |
| CI | Deterministic build and automated tests | Ephemeral GitHub runner; no persistent app | Local containers when database tests are added | Generated fixtures only | Pull request and push; automated gates |
| PR preview | Review UI and end-to-end behavior before merge | Vercel Preview projects | Non-production Supabase project by default; isolated Supabase branch when adopted | Seeded demo/synthetic data only | Non-production branch after CI; tester approval |
| Staging | Stable release-candidate verification | Vercel custom `staging` environment, or a documented branch-specific Preview fallback | Dedicated staging Supabase project | Seeded demo/synthetic data only | Explicit release-candidate deployment; milestone owner approval |
| Production | Real user service | Production web and API domains | Dedicated production Supabase project | Real account and health data | Protected `main`, production approval, release runbook |

### Isolation rules

- Preview and staging must never point to production Supabase, Storage, SMTP credentials, or API domains.
- Production credentials must never be downloaded into a normal developer `.env` file.
- A shared staging project is acceptable initially only with synthetic data and user-scoped test accounts. Concurrent branch collision risk must be documented in the active change plan.
- Supabase preview branches are the preferred later option for migration-heavy pull requests when the selected plan supports them.
- CI must not require hosted secrets for lint, typecheck, unit tests, or a production build. Runtime integration tests use a dedicated environment and explicit protection gate.
- Production migrations and application deployments use the same commit/release record; no ad hoc dashboard schema edits.

Provider audit on 2026-07-17 found an active `Health_Tracking` Supabase candidate (`gdccossstmochzfgjqxz`, `ap-southeast-1`) and no Vercel projects. The candidate is not yet designated staging: it has no repository migration history and contains an untracked public `SECURITY DEFINER` function reported by Security Advisor. Do not read keys, apply migrations, or configure applications against it until the user confirms its intended purpose and authorizes remediation/provisioning.

## Configuration classifications

- `public`: designed to be visible in browser bundles or URLs. It is still environment-specific configuration.
- `internal`: not a credential, but should normally remain server-side to reduce accidental coupling or disclosure.
- `secret`: grants provider or system access and must live only in an approved secret store.
- `sensitive data`: health, identity, location, source-file, or private incident content. This is not configuration and must never be placed in an environment variable unless an approved design explicitly requires it.

The prefix `NEXT_PUBLIC_` means the value is browser-visible. A variable with that prefix can never contain a secret.

## Runtime variable inventory

### Next.js web project

| Name | Class | Purpose | Local | Preview/staging | Production | Owner/store |
| --- | --- | --- | --- | --- | --- | --- |
| `NEXT_PUBLIC_APP_URL` | Public | Canonical app origin used for Auth redirects | `http://localhost:3000` | Exact auth-enabled preview or stable staging URL | Final HTTPS web domain | Local `.env.local`; Vercel web project |
| `NEXT_PUBLIC_API_BASE_URL` | Public | Browser-visible Go API origin | `http://localhost:8080` | Non-production API deployment | Production API domain | Local `.env.local`; Vercel web project |
| `NEXT_PUBLIC_SUPABASE_URL` | Public | Supabase project URL | Local API URL | Staging/preview project URL | Production project URL | Local `.env.local`; Vercel web project |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Public | Supabase browser API key used with user JWT/RLS | Local publishable key | Staging/preview publishable key | Production publishable key | Local `.env.local`; Vercel web project |
| `NEXT_PUBLIC_IMPORT_UPLOAD_ENABLED` | Public | Fail-closed Step 3 direct-upload release gate | `true` only during explicit local verification | `true` only during approved synthetic staging verification | `false` until production release approval | Local `.env.local`; Vercel web project |
| `NEXT_DIST_DIR` | Internal | Isolates generated Next.js output for concurrent local browser tests | `.next-e2e` only in the test-launched process | Not set | Not set | Browser test runner |

The web build is intentionally safe when Supabase variables are absent so generic CI can prerender the application. Auth runtime verification is still required in every auth-enabled deployed environment.

`NEXT_PUBLIC_IMPORT_UPLOAD_ENABLED` is a release gate, not an authorization control. Database RLS and private Storage policies remain authoritative. Keep the flag false when cleanup, cross-owner, or target-environment verification is incomplete.

`NEXT_PUBLIC_APP_URL` is currently an explicit value. Before arbitrary Vercel branch previews support Auth, either set a branch-specific Preview value or implement and test trusted forwarded-host/Vercel URL handling. Do not allow a preview login to redirect silently to localhost or production.

### Go API project

| Name | Class | Purpose | Local default/reference | Preview/staging | Production | Owner/store |
| --- | --- | --- | --- | --- | --- | --- |
| `PORT` | Internal | HTTP listen port | `8080` | Platform assigned | Platform assigned | Shell/runtime platform |
| `WEB_ORIGIN` | Internal | Exact browser origin permitted by API CORS | `http://localhost:3000` | Exact staging/preview web origin | Exact production web origin | Shell; Vercel API project |
| `SUPABASE_URL` | Internal | Base Supabase URL and JWKS source | `http://127.0.0.1:54321` | Staging/preview URL | Production URL | Shell; Vercel API project |
| `SUPABASE_PUBLISHABLE_KEY` | Public identifier/internal config | Go foreground Data/Storage API calls with the verified user JWT | Local publishable key | Staging/preview publishable key | Production publishable key | Shell; Vercel API project |
| `SUPABASE_JWT_ISSUER` | Internal | Exact JWT issuer | `<SUPABASE_URL>/auth/v1` | Hosted staging issuer | Hosted production issuer | Shell; Vercel API project |
| `SUPABASE_JWT_AUDIENCE` | Internal | Required access-token audience | `authenticated` | `authenticated` unless intentionally changed | `authenticated` unless intentionally changed | Shell; Vercel API project |

The API validates user JWTs with public JWKS and uses the public `SUPABASE_PUBLISHABLE_KEY` only while forwarding that verified JWT to owner-scoped Data/Storage APIs. It does not require a Supabase secret key. Adding `sb_secret_*` or legacy `service_role` access is a separate security-sensitive change: document the use case, prove the browser cannot reach it, minimize privileges, add rotation and audit steps, and update this inventory before implementation.

ADR 0002 accepts the Step 3 foreground path: forward the verified user JWT with the server-configured publishable key so RLS remains authoritative. Step 4 asynchronous workers need a separate least-privileged database/Storage credential decision because a browser JWT is short-lived. `DATABASE_URL` and `SUPABASE_SECRET_KEY` remain unconfigured and unauthorized.

### Local Supabase and provider variables

| Name | Class | Consumer | Location | Notes |
| --- | --- | --- | --- | --- |
| `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID` | Public identifier | Local Supabase Auth | Developer shell before `npx supabase start` | Must match the Google web client used for local Auth |
| `SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET` | Secret | Local Supabase Auth | Developer shell only | Referenced by `supabase/config.toml`; never put in web env files |

### Local browser-acceptance variables

| Name | Class | Consumer/location | Rule |
| --- | --- | --- | --- |
| `E2E_SUPABASE_URL` | Internal | Playwright config and owner-scoped test client; child process only | Derived by `e2e/run-browser-tests.mjs` from local CLI status; never committed |
| `E2E_SUPABASE_PUBLISHABLE_KEY` | Public | Isolated test web/API and owner-scoped assertions; child process only | Derived from local CLI status and paired with a user JWT for application data |
| `E2E_SUPABASE_ADMIN_KEY` | Secret | Playwright test setup/teardown only | Derived from the local stack, used only to create/delete generated Auth users, never passed to Next.js or Go, never printed or accepted for hosted targets |

The wrapper uses the repository's pinned Supabase CLI version, refuses to run when the local stack does not provide these values, and does not read hosted credentials. It strips every `E2E_*` variable from the temporary Next.js/Go environments and leaves zero generated Auth users or Storage objects after a passing run.

Hosted Google credentials are configured in each hosted Supabase project's Auth provider settings. They are not Vercel web variables.

### Hosted provider and deployment credentials

| Credential/configuration | Required now? | Approved store | Rule |
| --- | --- | --- | --- |
| Google OAuth client secret | Local validated; hosted planned | Local shell for local; Supabase Auth provider settings for hosted projects | Separate local/staging/production clients are preferred; rotate on exposure |
| SMTP password/API credential | Planned before production email Auth | Supabase Auth SMTP settings | Use a staging/sandbox sender separately from production |
| Supabase secret key | No | Server-only Vercel/Supabase secret store if later approved | Never expose to the browser; prefer user JWT + RLS |
| `VERCEL_TOKEN`, organization ID, project ID | No while Git integration is sufficient | GitHub protected environment secrets if custom CLI deployment is adopted | Use only for a documented deployment workflow; token is secret, IDs are internal |
| Supabase access token/database password for CI migrations | Planned | GitHub protected environment secrets or native Supabase GitHub integration | Production access only after environment approval |
| DNS registrar credential | Planned | Registrar/team secret manager | Never store in Vercel project variables unless an automation explicitly needs it |

Vercel Production and Preview secrets should be marked Sensitive when supported. Environment changes affect only new deployments, so verification always includes a redeploy.

## OAuth URL map

There are two different callback layers. They must not be confused.

| Configuration location | Local value/pattern | Hosted value/pattern | Purpose |
| --- | --- | --- | --- |
| Google Authorized JavaScript origin | `http://localhost:3000` | Exact app origin | Origin allowed to initiate Google login |
| Google Authorized redirect URI | Exact value from `supabase/config.toml`, currently `http://localhost:54321/auth/v1/callback` | `https://<project-ref>.supabase.co/auth/v1/callback` or configured custom Auth domain | Google returns to Supabase Auth here |
| Supabase Site URL | `http://localhost:3000` | Exact canonical app URL | Default email/Auth redirect target |
| Supabase additional Redirect URL | `http://localhost:3000/auth/callback` | Exact production callback; controlled preview pattern only where needed | Supabase returns the browser to the Next.js PKCE callback here |
| App `redirectTo` | `http://localhost:3000/auth/callback` | Current environment's `/auth/callback` | Application-selected PKCE completion route |

Google redirect URIs are exact and production uses HTTPS. Supabase may allow a controlled wildcard for Vercel preview app URLs, but production should use an exact callback. Test email confirmation, password reset, and Google login separately because they use related but distinct redirect configuration.

## Local bootstrap

### 1. Create ignored application configuration

From the repository root in PowerShell:

```powershell
Copy-Item apps/web/.env.example apps/web/.env.local
```

Fill only the public local values in `apps/web/.env.local`. `services/api/.env.example` is a reference; the Go process does not automatically load it.

### 2. Set provider secrets for the current shell

PowerShell:

```powershell
$env:SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID = "<local-client-id>"
$env:SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET = "<local-client-secret>"
```

Git Bash:

```bash
export SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID="<local-client-id>"
export SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET="<local-client-secret>"
```

These values must exist in the same shell that starts Supabase. PowerShell syntax such as `set $NAME=...` does not set an environment variable for the process.

### 3. Start local Supabase

```powershell
npx supabase --help
npx supabase start
npx supabase db reset
```

`npx supabase db reset` recreates the local database and removes local test users/data. Run it intentionally for clean migration verification; omit it for a normal restart.

`npx supabase status` displays both public and secret local values. Copy only the local Project URL and Publishable key into the web env file, and do not paste the full status output into chat, issues, or logs.

After changing Auth/provider environment variables or `supabase/config.toml`, restart the local stack:

```powershell
npx supabase stop
npx supabase start
```

### 4. Start the applications

API shell:

```powershell
cd services/api
$env:SUPABASE_URL = "http://127.0.0.1:54321"
$env:SUPABASE_JWT_ISSUER = "http://127.0.0.1:54321/auth/v1"
$env:SUPABASE_JWT_AUDIENCE = "authenticated"
go run ./cmd/api
```

Web shell:

```powershell
cd apps/web
npm run dev
```

Real-browser import acceptance uses isolated ports/build output and generated data, so it can run beside the normal dev servers:

```powershell
cd apps/web
npx playwright install chromium
npm run test:e2e:browser
```

The command requires local Supabase to be running. It starts temporary web/API processes, enables direct upload only in that web child process, and fails if ports `3102` or `8181` are already occupied.

Local email is captured by Mailpit at `http://127.0.0.1:54324`; it is intentionally not delivered to a real inbox.

## Provisioning a hosted non-production environment

Before enabling a remote Step 3 preview:

1. Create a dedicated Supabase staging project with no production data.
2. Apply repository migrations through the selected automated integration and verify a clean schema; do not reproduce schema manually in the dashboard.
3. Create a staging Google OAuth client and configure its exact hosted Supabase callback.
4. Configure Supabase Site URL and allowed app callbacks for the stable staging URL and any controlled Vercel preview pattern.
5. Configure a sandbox/custom SMTP sender if email delivery outside the Supabase team is required.
6. Create separate Vercel web and API projects with the correct repository root directories.
7. Set Preview or custom Staging variables from the inventory above; mark secrets Sensitive where supported.
8. Seed only synthetic demo accounts/data.
9. Deploy and verify email/password Auth, Google Auth, API JWT validation, RLS denial, and sign-out.
10. Record project names, owners, URLs, quotas, and evidence in the integration register without secret values.

## Production readiness

Production provisioning is Step 9 work, not an implicit side effect of local success. It requires:

- separate production Supabase, Vercel, Google OAuth, SMTP, and domain configuration;
- MFA and recovery ownership for provider accounts;
- exact HTTPS origins and callbacks;
- custom SMTP with SPF, DKIM, DMARC, link tracking disabled for Auth links, and deliverability tests;
- RLS/Storage policy tests, Security Advisor review, network/SSL settings, backup and restore decisions;
- rate-limit, quota, budget, and abuse-prevention review;
- protected production deployment and migration credentials;
- release, smoke-test, rollback, deletion, and incident procedures.

## Secret lifecycle

### Create

1. Confirm the credential is necessary and least-privileged.
2. Create it in the correct environment-specific provider project.
3. Store it directly in the approved store; do not route it through chat or Git.
4. Record only name, owner, provider, consumers, environments, created/review date, and rotation triggers.

### Use and audit

- Grant provider-console and secret-store access to the minimum maintainers.
- Require MFA on GitHub, Supabase, Vercel, Google Cloud, email, and DNS accounts.
- Review the inventory at least quarterly and before every production release. A review does not require rotating every healthy credential.
- Remove unused credentials and stale callback URLs promptly.
- Never print all environment variables or provider status output in CI logs.

### Rotate

Rotate when a value was exposed or may have been exposed, a maintainer loses access, provider guidance requires it, permissions change materially, or a scheduled risk review calls for it.

1. Create the replacement without deleting the old value when overlap is supported.
2. Update all consumers by environment and redeploy/restart them.
3. Verify authentication and failure monitoring.
4. Revoke the old value.
5. Record date, owner, affected consumers, and verification evidence without recording either value.

### Exposure response

Treat secrets pasted into chat, screenshots, issues, logs, source control, or build artifacts as exposed. Revoke or rotate at the provider, redeploy consumers, invalidate affected sessions where applicable, inspect audit logs privately, and add a preventive control. Deleting the visible message or local file alone does not restore secrecy.
