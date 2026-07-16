# Engineering documentation map

This directory is the operating manual for planning, building, releasing, and maintaining Health Tracking. Product intent stays stable; delivery status and implementation detail remain easy to revise.

## Sources of truth

| Document | Question it answers | Update cadence |
| --- | --- | --- |
| [`PROJECT_PLAN.md`](../PROJECT_PLAN.md) | What are we building, why, and within which architecture and safety boundaries? | Only when product scope or architecture changes |
| [`IMPLEMENTATION_STEPS.md`](IMPLEMENTATION_STEPS.md) | Which outcomes must be delivered, in what order, and what proves each milestone is complete? | When milestone scope, dependencies, or gates change |
| [`DELIVERY_TRACKER.md`](DELIVERY_TRACKER.md) | What is happening now, what is blocked, and what decision is next? | Every meaningful handoff or scope change |
| [`ENGINEERING_WORKFLOW.md`](ENGINEERING_WORKFLOW.md) | How does a change move from idea to production? | When the SDLC changes |
| [`ENVIRONMENTS_AND_SECRETS.md`](ENVIRONMENTS_AND_SECRETS.md) | Where does the system run, which configuration exists, and where may secrets live? | Every environment or variable change |
| [`THIRD_PARTY_INTEGRATIONS.md`](THIRD_PARTY_INTEGRATIONS.md) | Which external services are used, who owns them, and how are they verified or removed? | Every provider change and quarterly review |
| [`RELEASE_RUNBOOK.md`](RELEASE_RUNBOOK.md) | How is a release promoted, verified, and rolled back? | Every release-process change; instantiate for each production release |
| [`auth-supabase.md`](auth-supabase.md) | How is Supabase Auth operated locally and prepared for hosted environments? | Every Auth/provider change |
| [`design/brand-and-ui-brief.md`](design/brand-and-ui-brief.md) | What visual and content direction should the product follow? | When design direction changes |

Templates live in [`templates/`](templates/). A non-trivial change starts from `CHANGE_PLAN.md`; an architecture decision uses `ADR.md`; a production release uses `RELEASE_RECORD.md`.

Instantiated active/upcoming plans live in [`plans/`](plans/). The proposed Step 3 plan is [`plans/0003-import-manifest-upload.md`](plans/0003-import-manifest-upload.md).

## Planning hierarchy

```text
Product and architecture baseline
  -> milestone outcome and acceptance gate
    -> living delivery tracker
      -> change plan with work packages and risk analysis
        -> pull request with evidence
          -> release record and operational evidence
```

Do not copy the same mutable status into several documents. The tracker owns current status. The environment and integration documents own operational configuration metadata. The project plan owns long-lived product constraints.

## Required document updates

A pull request must update documentation when it changes any of the following:

- product scope, user-visible behavior, or a milestone acceptance criterion;
- an environment variable, secret, callback URL, domain, port, or deployment target;
- a database migration, retention rule, data classification, RLS policy, or Storage policy;
- a third-party provider, permission, quota, billing assumption, owner, or failure mode;
- a build, test, release, rollback, incident, or deletion procedure;
- an accepted architectural decision or a superseded decision.

Never store credential values, personal Huawei data, health values, access tokens, or private incident evidence in these documents.
