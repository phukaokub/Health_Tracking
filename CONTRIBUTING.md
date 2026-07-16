# Contributing

Health Tracking is developed in verified milestones with strict privacy and environment separation.

## Before changing code

1. Read the [documentation map](docs/README.md) and [engineering workflow](docs/ENGINEERING_WORKFLOW.md).
2. Check the current milestone, blockers, and decisions in the [delivery tracker](docs/DELIVERY_TRACKER.md).
3. For a non-trivial change, copy the [change-plan template](docs/templates/CHANGE_PLAN.md) and complete its applicable sections.
4. Confirm no personal Huawei export, real health data, credentials, JWTs, user email addresses, or private incident evidence will enter Git, fixtures, logs, screenshots, or pull-request content.

## Branch and review

- Start from the latest `main` and use a short-lived `codex/<change-name>` or feature branch.
- Keep commits coherent and use descriptive imperative messages.
- Open a pull request using [the repository template](.github/pull_request_template.md).
- Update environment, integration, migration, decision, and runbook documentation in the same pull request as the behavior it describes.
- Do not claim hosted or production setup based only on source-code support; provider-side verification is separate evidence.

## Baseline checks

Documentation:

```text
node scripts/check-docs.mjs
```

Web:

Start `npm run dev` in another terminal before the E2E command.

```text
cd apps/web
npm ci
npm run lint
npm run typecheck
npm run test:unit
npm run build
npm run test:e2e
```

API:

```text
cd services/api
gofmt -l .
go vet ./...
go test ./...
```

Supabase changes:

```text
npx supabase --help
npx supabase db reset
npx supabase db lint --local --fail-on error
npx supabase test db --local supabase/tests
```

`npx supabase db reset` deletes/recreates local database state. Use it intentionally for migration verification and never point it at a hosted project.

Run only commands that apply, but explain any skipped required gate. Milestone-specific tests are defined in [implementation steps](docs/IMPLEMENTATION_STEPS.md).

## Completion

A change is not done until applicable code, migrations, provider/environment configuration, tests, documentation, security/privacy checks, user verification, and merge/release evidence are complete. Use the precise status language in the engineering workflow.
