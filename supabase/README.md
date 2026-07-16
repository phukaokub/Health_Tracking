# Supabase local environment

Supabase is reserved for Auth, Postgres, private Storage, and local migrations. The CLI is not committed to the repository; run it through `npx supabase` and discover the installed command surface with `npx supabase --help` before operating the local project.

The first database migration belongs to Step 2 (Auth, profiles, and RLS). Do not add production credentials or personal Huawei data to this folder.

Operational references:

- [`docs/auth-supabase.md`](../docs/auth-supabase.md) for local Auth, Mailpit, and Google setup;
- [`docs/ENVIRONMENTS_AND_SECRETS.md`](../docs/ENVIRONMENTS_AND_SECRETS.md) for environment and credential boundaries;
- [`docs/THIRD_PARTY_INTEGRATIONS.md`](../docs/THIRD_PARTY_INTEGRATIONS.md) for hosted Supabase ownership and release gates.
