# Health Tracking

This repository contains a private, non-clinical health tracking application built in verified milestones.

- [Project architecture plan](PROJECT_PLAN.md)
- [Engineering documentation map](docs/README.md)
- [Implementation steps and environment/release gates](docs/IMPLEMENTATION_STEPS.md)
- [Current delivery tracker](docs/DELIVERY_TRACKER.md)
- [Engineering workflow](docs/ENGINEERING_WORKFLOW.md)
- [Environments and secrets](docs/ENVIRONMENTS_AND_SECRETS.md)
- [Third-party integration register](docs/THIRD_PARTY_INTEGRATIONS.md)
- [Release runbook](docs/RELEASE_RUNBOOK.md)
- [Contributing workflow](CONTRIBUTING.md)
- [Brand and UI prompt brief](docs/design/brand-and-ui-brief.md)

Current status is recorded only in the delivery tracker. A milestone is not complete merely because its code exists: local/staging flows, provider configuration, tests, documentation, user acceptance, and merge/release state are separate gates.

## Step 0 local baseline

Run the web app:

```text
cd apps/web
npm run dev
```

Run the API in a second terminal:

```powershell
cd services/api
go run ./cmd/dev
```

This starts local Supabase, derives the local public key for the API process,
and then starts the Go service. It does not use hosted staging configuration.
It reports safe progress without printing keys or secrets. `./start-local.cmd`
from the repository root is an equivalent Windows shortcut.
Before the first run, copy `.env.local.example` to `.env.local` and add the
local Google OAuth client ID and secret once.

The Supabase CLI is required from Step 2 onward and is run through `npx`:

```text
npx supabase --help
npx supabase start
```

## Step 2 local Supabase Auth baseline

The local Supabase project includes a `profiles` table with owner-only RLS policies and an auth trigger that creates a profile for each new user. See [Supabase Auth local setup](docs/auth-supabase.md) for local environment variables and Google OAuth provider notes.

Local confirmation/reset email is intentionally captured in Mailpit at `http://127.0.0.1:54324`; it is not sent to the real inbox entered during local sign-up.

## Starting a new work package

1. Confirm the milestone and current gate in the [delivery tracker](docs/DELIVERY_TRACKER.md).
2. Copy the [change-plan template](docs/templates/CHANGE_PLAN.md) and complete the applicable environment, integration, migration, security, test, rollout, and rollback sections.
3. Work on a short-lived branch and open a pull request using the repository template.
4. Record evidence and status without copying credentials, email addresses, health values, or raw Huawei content.
