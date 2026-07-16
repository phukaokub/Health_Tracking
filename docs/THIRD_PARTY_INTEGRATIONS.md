# Third-party integrations

This register covers every external service that can affect development, authentication, deployment, data handling, availability, or cost. Source-code support and provider-side configuration are tracked separately.

## Status vocabulary

- `validated local`: the local flow has direct evidence.
- `active`: currently used in a persistent environment.
- `planned`: accepted but not provisioned or verified.
- `decision required`: provider or topology has not been selected.
- `disabled`: intentionally unavailable; the user flow must degrade clearly.
- `retiring`: replacement and credential/data cleanup are in progress.

## Integration register

| Integration | Purpose and data | Environments | Status on 2026-07-17 | Credential/configuration owner | Verification and failure behavior |
| --- | --- | --- | --- | --- | --- |
| GitHub repository and Actions | Source, pull requests, CI metadata; no health data | Development/CI | Active | Repository maintainer; GitHub settings | PR checks run; if unavailable, do not merge/release and retain local evidence |
| Local Supabase CLI/Docker | Auth, Postgres, Studio, Storage, Mailpit using synthetic data | Local | Active | Repository config plus developer machine | `npx supabase start`, clean reset, Auth/RLS tests; local outage blocks integration tests only |
| Hosted Supabase staging | Non-production Auth, Postgres, private Storage | Preview/staging | Planned before remote Step 3 verification | Supabase project owner | Migration, Auth, RLS, Storage, quota, and API health checks; previews fail closed if unavailable |
| Hosted Supabase production | Production Auth, Postgres, private Storage containing user data | Production | Planned for Step 9 | Supabase organization/project owners | Release smoke, RLS denial, backup/restore posture, alerts; stop release on failure |
| Google OAuth local client | Identity using `openid`, email, and profile information | Local | Validated local | Google Cloud project owner; local secret in shell | Login and callback complete; email/password remains available if provider fails |
| Google OAuth hosted clients | Identity only; no Google API access or provider-token retention | Staging/production | Planned | Google Cloud project owner; secret in corresponding Supabase project | Separate client per environment preferred; exact callback and consent-screen test |
| Mailpit | Captures local Auth email; no external delivery | Local | Active | Local Supabase stack | Confirmation/reset message appears at port 54324; never expect a real inbox message |
| Playwright/Chromium | Real-browser Auth/import acceptance using generated ZIP bytes and generated users only | Local/CI | Validated local and in PR #11 CI; pinned `@playwright/test` 1.61.1 | Repository lockfile and developer/CI browser cache | `npm run test:e2e:browser`; failure retains runner-local trace/screenshot artifacts that must not contain real user data |
| Transactional Auth SMTP | Confirmation, reset, and security email | Staging/production | Decision required before public email Auth | Email-provider and Supabase owners | Delivery, SPF/DKIM/DMARC, template links, bounce/rate-limit checks; Google login can remain fallback |
| Vercel web project | Builds and serves Next.js | Preview/staging/production | Planned; local build is active | Vercel team/project owner | Build, page/Auth smoke, env audit, deployment diagnostics; rollback to known-good deployment |
| Vercel API project | Builds and serves Go API | Preview/staging/production | Planned | Vercel team/project owner | Health/JWKS/authenticated route smoke; web must show a safe unavailable state on outage |
| Background parser runtime | Executes bounded Step 4 normalization jobs; reads private import objects and writes normalized records | Staging/production | Decision required; proposal in ADR 0005 | Runtime, Supabase, and operations owners | Lease/checkpoint, timeout, retry, owner isolation, and synthetic failure probes must pass before enabling triggers |
| DNS and custom domains | Stable web, API, and optional Auth/email domains | Staging/production | Decision required before Step 9 | Domain registrar/DNS owner | DNS/TLS checks and documented rollback to platform domains |
| Error monitoring/observability provider | Redacted errors, traces, uptime, release health | Staging/production | Decision required in Step 8 | Operations owner | Synthetic failure and alert routing test; must never collect health values, JWTs, emails, GPS, or raw files |

Docker Desktop, Node.js, Go, and the Supabase CLI are development dependencies. Pin supported versions in CI and onboarding documentation; review major upgrades as integration changes when they can alter local data or generated artifacts.

## Required integration record

Before enabling a new provider or materially changing one, add or update a record containing:

- provider, purpose, current status, technical owner, billing owner, and recovery owner;
- account/organization/project names or IDs that are safe to record;
- local, preview, staging, and production separation;
- data sent, data received, data retention, subprocessors/data region considerations, and user disclosure;
- permissions/scopes and why each is required;
- configuration and credential names, approved stores, consumers, and rotation triggers;
- origins, redirect URIs, webhook URLs, domains, network allowlists, and signature verification;
- free-tier/plan assumptions, quotas, rate limits, expected cost trigger, and budget alert;
- dependency/version pinning and provider changelog owner;
- happy path, denial path, timeout/outage behavior, retry/idempotency, and alerting;
- rollout, rollback, offboarding, credential revocation, and provider-held data deletion;
- verification date and links to non-sensitive evidence.

Use the integration section in [`templates/CHANGE_PLAN.md`](templates/CHANGE_PLAN.md) for a change-specific delta. Do not put secret values in the record.

## Provider runbooks

### Supabase

Responsibilities:

- Auth, user JWT issuance, Postgres, private Storage, migrations, and RLS;
- local Mailpit capture; hosted SMTP configuration;
- separate staging and production projects.

Controls:

- Run the CLI through `npx supabase` and inspect the available command surface with `npx supabase --help`.
- Commit migrations and policies; use clean local reset, lint, and policy tests before hosted deployment.
- Use the publishable key in browser code and in the Go foreground adapter only with the verified user JWT. A secret key or legacy `service_role` key is not currently required.
- Enable RLS and explicit grants for exposed tables and Storage objects. Test one user cannot access another user's rows or object paths.
- Do not use `user_metadata` for authorization decisions.
- Review current Supabase breaking changes before upgrades or production releases.
- Prefer an automated GitHub/Supabase migration path over manual production `db push` from a workstation.

Failure/rollback:

- Auth or database outage blocks private application flows; show a safe retry state and do not bypass Auth.
- Roll application deployments back independently only when migrations remain backward-compatible.
- Repair database mistakes with reviewed forward migrations; restore from backup only under the incident runbook.

### Google OAuth

Purpose is sign-in only. The application does not request Google Drive, Calendar, health, or other Google API scopes and does not store Google provider access/refresh tokens.

For each environment:

1. Create/select the correct Google Cloud project and configure the OAuth consent screen.
2. Create a Web application client.
3. Add the exact application origin.
4. Add the exact Supabase Auth callback, not the Next.js callback, as the Google redirect URI.
5. Store the client secret only in the corresponding local shell or hosted Supabase Auth settings.
6. Configure the app callback in Supabase's redirect allowlist.
7. Test success, denial, invalid configuration, sign-out, and email/password fallback.
8. Move from test to production consent status only after domains, privacy information, and test users are correct.

Use separate clients for local, staging, and production where practical. Rotating a client secret requires updating Supabase Auth and restarting/redeploying the affected environment.

### Auth email and Mailpit

Mailpit is the expected local email inbox. It captures mail inside the local Supabase stack and never sends it to the address entered during sign-up.

Hosted Supabase's default email service is for limited testing, not production. Before public email/password Auth:

- select a transactional SMTP provider and a dedicated Auth sending domain/address;
- configure separate staging and production credentials;
- set SPF, DKIM, and DMARC;
- disable link tracking that can rewrite single-use Auth URLs;
- review confirmation/reset templates, redirect URLs, rate limits, abuse controls, bounce handling, and deliverability;
- test with several mailbox providers without logging recipient addresses or message contents.

Provider selection must record expected volume, free-tier limits, cost threshold, region/data handling, account recovery, and a fallback plan.

### Vercel

Create two projects from this monorepo:

| Project | Root | Responsibility | Required environment groups |
| --- | --- | --- | --- |
| Web | `apps/web` | Next.js UI, SSR Auth cookies, OAuth callback | Preview/staging and Production public web configuration |
| API | `services/api` | Go API, JWT/JWKS validation, import orchestration | Preview/staging and Production API configuration |

Controls:

- Connect GitHub for branch previews and production deployment unless a reviewed custom workflow replaces it.
- Scope environment variables separately to Preview/Staging and Production. Use branch-specific Preview values when needed.
- Mark server credentials Sensitive and keep all `NEXT_PUBLIC_*` values non-secret.
- Pin the CLI if CI begins using it; protect any `VERCEL_TOKEN` as a production deployment secret.
- Ensure web and API deployments identify the same commit/release.
- Test build behavior with no secrets and runtime behavior with the target environment configuration.
- A Vercel rollback changes the served application deployment; it does not roll back Supabase migrations or restore environment-variable values.

### GitHub

Controls:

- Protect `main`, block force-push/deletion, and require unique CI checks.
- Use pull requests and the repository template for all non-emergency changes.
- Store workflow credentials at the narrowest repository/environment scope. A production job should reference a protected `production` environment where the plan supports required reviewers.
- Restrict production deployment branches to protected `main` and prevent self-approval where available.
- Prefer provider Git integrations or OIDC-style short-lived runtime access over long-lived tokens. Vercel CLI deployment still requires a Vercel token if that workflow is adopted.
- Never echo environment inventories, tokens, raw authorization headers, or provider status output into Actions logs.

## Open integration decisions

| ID | Decision | Needed by | Default until decided |
| --- | --- | --- | --- |
| INT-001 | Shared staging Supabase versus per-PR Supabase Branching | Before remote migration/Storage verification in Step 3 | Shared staging with synthetic data and explicit collision risk |
| INT-002 | Vercel custom Staging environment versus branch-specific Preview fallback | Before first stable hosted release candidate | Branch-specific Preview; document exact branch and URLs |
| INT-003 | Transactional SMTP provider and Auth sending domain | Before external beta or production email/password Auth | Mailpit locally; hosted email limited to controlled testing |
| INT-004 | Production web/API domain and DNS provider | Before Step 9 production configuration | Platform domains only; no production launch |
| INT-005 | Error monitoring, tracing, and uptime provider | During Step 8 | Structured local/platform logs with strict redaction; no health telemetry |
| INT-006 | Supabase/Vercel plan upgrades for backups, branching, quotas, and availability | Before load/production readiness sign-off | Do not assume paid-only capability; document current limits |
| INT-007 | Go foreground/background Supabase access model and least-privileged worker credential | Before Step 4 worker execution | Foreground accepted in ADR 0002; review the least-privileged worker proposal in ADR 0005 before implementation |

Accepted decisions move to an ADR when they are architectural or expensive to reverse, and their implementation status remains in [`DELIVERY_TRACKER.md`](DELIVERY_TRACKER.md).

## Provider reference set

Review these primary sources before the relevant implementation/release; provider limits and UI paths can change. Last reviewed for this workflow: 2026-07-15.

- Supabase: [breaking-change changelog](https://supabase.com/changelog?tags=breaking-change), [deployment/branching](https://supabase.com/docs/guides/deployment), [production checklist](https://supabase.com/docs/guides/deployment/going-into-prod), and [API keys](https://supabase.com/docs/guides/getting-started/api-keys).
- Supabase Auth: [Google login](https://supabase.com/docs/guides/auth/social-login/auth-google), [redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls), and [custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp).
- Supabase Storage: [resumable uploads](https://supabase.com/docs/guides/storage/uploads/resumable-uploads), [access control](https://supabase.com/docs/guides/storage/security/access-control), [ownership](https://supabase.com/docs/guides/storage/security/ownership), and [Storage schema safety](https://supabase.com/docs/guides/storage/schema/design).
- Vercel: [environment variables](https://vercel.com/docs/environment-variables), [managing variables across environments](https://vercel.com/docs/environment-variables/manage-across-environments), [deployment promotion/rollback](https://vercel.com/docs/deployments/promoting-a-deployment), and [Function limits](https://vercel.com/docs/functions/limitations).
- Playwright: [test web servers](https://playwright.dev/docs/test-webserver) and [locator file upload](https://playwright.dev/docs/input#upload-files).
- GitHub: [protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) and [deployment environments/protection](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).
- Google: [OAuth web-server credentials and redirect validation](https://developers.google.com/identity/protocols/oauth2/web-server) and [OAuth policies](https://developers.google.com/identity/protocols/oauth2/policies).
