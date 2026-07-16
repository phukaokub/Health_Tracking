# Health Tracking web

This Next.js application owns public pages, Supabase SSR Auth/session cookies, the OAuth callback, account UI, and future import/report/dashboard flows.

## Local configuration

Copy `.env.example` to `.env.local` and set the local public values. Every `NEXT_PUBLIC_*` value is visible in the browser and must never contain a secret.

See:

- [`../../docs/auth-supabase.md`](../../docs/auth-supabase.md) for local email/Google Auth;
- [`../../docs/ENVIRONMENTS_AND_SECRETS.md`](../../docs/ENVIRONMENTS_AND_SECRETS.md) for environment-specific values and secret boundaries.

## Commands

```text
npm ci
npm run dev
npm run lint
npm run typecheck
npm run test:unit
npm run build
npm run test:e2e
```

Open `http://localhost:3000`. The web app expects the Go API at the configured `NEXT_PUBLIC_API_BASE_URL` and local Supabase at `NEXT_PUBLIC_SUPABASE_URL`.

Direct import upload is fail-closed. Set `NEXT_PUBLIC_IMPORT_UPLOAD_ENABLED=true` only for an approved local or synthetic staging verification window; keep it `false` until Step 3 cleanup and cross-owner gates are complete.

The production build intentionally succeeds when Supabase runtime configuration is absent so generic CI can validate source. An auth-enabled deployment is not accepted until runtime Auth flows are verified with the target environment variables and provider configuration.
