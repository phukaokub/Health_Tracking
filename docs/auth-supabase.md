# Supabase Auth setup and verification

Step 2 uses Supabase Auth for confirmed email/password accounts and Google OAuth with a Next.js PKCE callback. This guide covers local operation and the boundary to hosted configuration. Environment ownership and production requirements are in [`ENVIRONMENTS_AND_SECRETS.md`](ENVIRONMENTS_AND_SECRETS.md).

## Secret safety

- Use the Supabase publishable key in the web app. Do not use an `sb_secret_*` or legacy `service_role` key in browser code.
- Keep the Google client secret only in the shell that starts local Supabase or in hosted Supabase Auth settings.
- Never paste provider secrets, full `npx supabase status` output, `.env.local`, JWTs, or user email addresses into chat, issues, screenshots, logs, or Git.
- A secret that was pasted or otherwise disclosed must be rotated at its provider. Deleting the message or local file is not enough.

## Prerequisites

- Docker Desktop is running.
- Node/npm dependencies are installed for `apps/web`.
- Use the repository-local CLI path and inspect the installed command surface:

```text
npx supabase --version
npx supabase --help
```

## Local Google variables

The names must match `supabase/config.toml` and must exist in the process that runs `npx supabase start`.

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

Do not use `set $NAME=...` in PowerShell; that does not create the environment variable expected by the child process.

## Start/reset local Supabase

From the repository root:

```text
npx supabase start
npx supabase db reset
```

`npx supabase db reset` is destructive to local users/data: it recreates the local database from migrations. Use it for a clean migration test, not every time you start the stack.

After changing Google variables or `supabase/config.toml`, restart:

```text
npx supabase stop
npx supabase start
```

`npx supabase status` includes both public and secret local values. Copy only:

- Project URL -> `NEXT_PUBLIC_SUPABASE_URL`
- Publishable -> `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`

Do not copy the Secret value into the web application.

## Web configuration

Create `apps/web/.env.local` from `apps/web/.env.example` and set:

```text
NEXT_PUBLIC_APP_URL=http://localhost:3000
NEXT_PUBLIC_API_BASE_URL=http://localhost:8080
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<local-publishable-key>
```

The code uses `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, not the legacy project variable name `NEXT_PUBLIC_SUPABASE_ANON_KEY`.

Run from the web directory because the repository has no root Node package:

```text
cd apps/web
npm run dev
```

## API configuration

The Go process does not load `.env` automatically. In a separate PowerShell session:

```powershell
cd services/api
$env:SUPABASE_URL = "http://127.0.0.1:54321"
$env:SUPABASE_JWT_ISSUER = "http://127.0.0.1:54321/auth/v1"
$env:SUPABASE_JWT_AUDIENCE = "authenticated"
go run ./cmd/api
```

The current verifier uses Supabase's public JWKS. It does not need a secret/service-role key.

## Local email behavior

Email confirmations are enabled. Local Auth sends messages to Mailpit, not to the real mailbox entered in the form.

1. Sign up with a test email/password.
2. Open `http://127.0.0.1:54324`.
3. Open the confirmation message and follow the link.
4. Sign in with the confirmed credentials.

An unconfirmed account or an invented address whose confirmation was never opened should not be expected to sign in successfully.

## Google OAuth configuration

Create a Google OAuth client of type **Web application**.

Local configuration must match exactly:

- Authorized JavaScript origin: `http://localhost:3000`
- Authorized redirect URI: `http://localhost:54321/auth/v1/callback`

The Google redirect URI points to Supabase Auth. Supabase then redirects to the app callback at `http://localhost:3000/auth/callback`, which exchanges the PKCE code and stores the session cookie.

If you change the host between `localhost` and `127.0.0.1`, update Google and `supabase/config.toml` together; OAuth redirect matching is exact.

## Verification checklist

- [ ] Sign-up shows a check-email state.
- [ ] Mailpit receives the message and its confirmation link returns to the app.
- [ ] Confirmed email/password signs in; invalid password shows a safe error.
- [ ] Google login completes Google -> Supabase -> Next.js and lands on `/account`.
- [ ] `/account` shows the signed-in profile read through owner-only RLS.
- [ ] Sign-out removes access to account data.
- [ ] Missing/invalid API bearer token is rejected.
- [ ] User A cannot read or update User B's profile.
- [ ] `npm run lint`, `npm run typecheck`, `npm run build`, `npm run test:e2e`, and `go test ./...` pass.

## Common failures

### `Unsupported provider: provider is not enabled`

The local Google variables were not visible to the process that started Supabase, the provider was disabled, or the stack was not restarted. Set variables in the same PowerShell/Git Bash session, then stop/start Supabase.

### Google `Error 401: invalid_client`

The client ID/secret pair is wrong, belongs to another client/project, or was rotated without updating local Auth. Verify the Web client and replace/rotate the secret at Google; do not paste it into diagnostics.

### Sign-up says check email but no real email arrives

This is normal locally. Use Mailpit at port 54324.

### Email/password says invalid credentials

Open the Mailpit confirmation first, verify the exact email/password, and inspect the local Auth user in Studio. Creating another unconfirmed account does not bypass confirmation.

### Account page says Supabase is not configured

Confirm `.env.local` uses `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, restart `npm run dev`, and ensure the Project URL matches the running local stack.

## Hosted staging and production

Local success does not configure hosted Supabase automatically. Each hosted environment needs:

- a separate Supabase project and publishable key/URL;
- Site URL and app redirect allowlist for that environment;
- a separate Google OAuth client where practical, using the hosted Supabase callback `https://<project-ref>.supabase.co/auth/v1/callback`;
- Google credentials stored in Supabase Auth provider settings, not the Vercel web project;
- custom SMTP before public email/password use, with sender-domain authentication and link tracking disabled;
- Vercel environment-scoped web/API configuration, RLS/cross-user tests, and hosted Auth smoke tests.

Track these actions in [`THIRD_PARTY_INTEGRATIONS.md`](THIRD_PARTY_INTEGRATIONS.md) and verify them through the release gates. Do not reuse a local/test Google secret as the production secret.

## Privacy wording

Health Tracking is a non-clinical wellness application. Authentication protects user-owned data, but the product must not claim diagnosis, medical-device interpretation, treatment guidance, raw ECG waveform analysis, or medical outcome prediction.
