# Agent delivery contract

This file is the operational contract for coding agents in this repository.
It supplements, but does not replace, the SDLC in `docs/ENGINEERING_WORKFLOW.md`.
If a user instruction conflicts with this file, follow the user instruction.

## Start every task

1. Read `docs/DELIVERY_TRACKER.md` and the relevant implementation plan.
2. State the requested milestone, user-visible outcome, explicit non-goals, and
   whether the task includes any external mutation.
3. Inspect the current branch and working tree before changing files.
4. For a non-trivial change, use the applicable change plan. Do not create a
   second plan when an accepted one already covers the work.

## Scope and delivery guardrails

- Default to **one accepted milestone slice, one branch, and one pull request**.
  Do not split a slice into multiple PRs merely to make intermediate progress
  visible. Split only when the user asks, or when a documented compatibility or
  review boundary makes independent merge/release necessary.
- Do not start the next numbered milestone while the requested milestone is
  active. Planning a later milestone is allowed only when explicitly requested.
- Do not provision, alter, or audit hosted providers, deployment targets,
  OAuth/SMTP settings, secrets, domains, or production/staging resources unless
  the user explicitly includes that work in the request. Source-code support is
  not evidence that a hosted integration is complete.
- If a required decision would materially change security, cost, data handling,
  provider ownership, or release scope, stop after recording the exact decision
  needed. Do not substitute exploratory work for the decision.
- Keep unrelated refactors, dependency upgrades, documentation rewrites, and
  workflow changes out of a feature PR unless they are required for the agreed
  outcome.

## Efficient execution

- Make a short implementation plan, then build. Do not repeatedly re-plan or
  re-audit the same evidence without a changed condition.
- Run the smallest relevant local checks while developing. Run the complete
  affected command matrix once before opening a PR.
- Do not rerun a passing expensive check (local Supabase, browser E2E, or full
  CI) unless relevant code/configuration changed, the prior run failed, or the
  user asks for another run.
- When CI is required, open one PR, wait for its checks, and merge only after
  required checks are green. Report a failed check with its cause and proposed
  fix before changing unrelated code.
- Do not repeatedly poll an unchanged remote run. Use a reasonable wait and
  report only a meaningful state change, failure, or completion.
- Prefer local synthetic fixtures. Never print or commit credentials, user
  emails, raw health data, tokens, full provider status output, or screenshots
  containing them.

## Definition of done and status language

Only call a milestone `done` when its agreed acceptance criteria, applicable
tests, documentation, user verification, and merge evidence are complete.
Use `implementation complete; hosted verification pending` when provider work
is outside the accepted request or still needs approval.

Each handoff/final update must contain only:

1. outcome and evidence;
2. PR/merge status, if applicable;
3. the one next action or exact blocker.

Do not confuse GitHub PR numbers with roadmap step numbers. Write both when
needed, for example: `Step 3, PR #11`.

## Model and collaboration routing

- Use a fast implementation model (for example Luna) for bounded coding and
  test fixes.
- Use Terra/Sol for architecture, security-sensitive design, or a genuinely
  ambiguous failure; return to the faster model once the decision is made.
- Model choice never authorizes broader scope. The delivery guardrails above
  remain in force for every model and tool.

## Required references

- SDLC and definition of done: `docs/ENGINEERING_WORKFLOW.md`
- Current status and decisions: `docs/DELIVERY_TRACKER.md`
- Environment and secret rules: `docs/ENVIRONMENTS_AND_SECRETS.md`
- Third-party integration register: `docs/THIRD_PARTY_INTEGRATIONS.md`
- Pull-request evidence template: `.github/pull_request_template.md`
