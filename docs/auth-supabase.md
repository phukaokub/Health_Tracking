# Supabase Auth local setup

Step 2 uses Supabase Auth for email/password sign-up and optional Google OAuth. Keep all Supabase service-role keys and provider secrets in local environment files only; do not commit them.

## Local start

```text
npx supabase --help
npx supabase start
npx supabase db reset
```

The local Auth site URL is `http://localhost:3000`, and the OAuth callback route is `http://localhost:3000/auth/callback`.

## Web environment

Set these values in `apps/web/.env.local` when the local Supabase stack is running:

```text
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<publishable key from npx supabase status>
```

The included local configuration requires email confirmation. After sign-up, open Mailpit at `http://127.0.0.1:54324`, open the confirmation message, and follow its link to finish local sign-in. Restart the local stack after changing this setting with `npx supabase stop` then `npx supabase start`.

The follow-up `grant_profiles_data_api_access` migration gives the `authenticated` role table access; the existing RLS policies still limit each user to their own profile row.

Run web commands from `apps/web`, because this repository does not have a root
Node package:

```text
cd apps/web
npm install
npm run dev
```

## Google OAuth provider

1. Create a Google OAuth web client in Google Cloud Console.
2. Add `http://localhost:54321/auth/v1/callback` as an authorized redirect URI for local development.
3. Export the client ID and secret locally as `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID` and `SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET`.
4. Change `[auth.external.google].enabled` to `true` in `supabase/config.toml` for local provider testing.

## Privacy wording

Health Tracking is a non-clinical wellness application. Authentication protects access to user-owned profile and future health rows, but the product must not present diagnoses, medical-device claims, raw Huawei exports, raw GPS tracks, or raw ECG waveform data by default.
