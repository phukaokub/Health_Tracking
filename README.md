# Health Tracking

This repository contains a private, non-clinical health tracking application built in verified milestones.

- [Project architecture plan](PROJECT_PLAN.md)
- [Implementation steps and local verification gates](docs/IMPLEMENTATION_STEPS.md)
- [Brand and UI prompt brief](docs/design/brand-and-ui-brief.md)

## Step 0 local baseline

Run the web app:

```text
cd apps/web
npm run dev
```

Run the API in a second terminal:

```text
cd services/api
go run ./cmd/api
```

The Supabase CLI is required from Step 2 onward. It is intentionally not required for the Step 0 hello-world baseline.

## Step 2 local Supabase Auth baseline

The local Supabase project includes a `profiles` table with owner-only RLS policies and an auth trigger that creates a profile for each new user. See [Supabase Auth local setup](docs/auth-supabase.md) for local environment variables and Google OAuth provider notes.
