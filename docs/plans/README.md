# Work plans

This directory contains instantiated change plans for active or upcoming work packages. Use the template in [`../templates/CHANGE_PLAN.md`](../templates/CHANGE_PLAN.md).

- A plan begins as `proposed` and must pass Definition of Ready before implementation.
- Update status, decisions, scope deltas, and evidence in place while the change is active.
- Keep current milestone summary in [`../DELIVERY_TRACKER.md`](../DELIVERY_TRACKER.md); link here for exact detail rather than copying it.
- After completion, retain the plan as an implementation record. Do not rewrite accepted history; append changes and link a superseding plan or ADR.
- Never store environment values, credentials, user identifiers, health data, raw source paths, or private incident evidence.

Current plans:

- [`0003-import-manifest-upload.md`](0003-import-manifest-upload.md) — Step 3 implementation record; hosted/browser acceptance remains.
- [`0004-huawei-json-normalization.md`](0004-huawei-json-normalization.md) — proposed Step 4 implementation plan.
- [`0004-source-coverage-matrix.md`](0004-source-coverage-matrix.md) — proposed Step 4 source and metric boundary.
