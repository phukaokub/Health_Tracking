# ADR 0003: Browser resumable-upload client

- Status: accepted
- Date: 2026-07-16
- Decision owners: repository maintainer with Codex implementation support
- Related milestone/change/PR: Step 3 / 3E / `codex/step-3-tus-upload`
- Supersedes / superseded by: none

## Context

Step 3 sends immutable logical file parts directly from the authenticated browser to private Supabase Storage. The upload must resume after interruption, keep source bodies out of Next.js and Go, use Supabase's required TUS transport behavior, and avoid placing access tokens, upload URLs, raw paths, or filenames in logs or application metadata.

## Decision drivers

- Compatibility with Supabase Storage's documented TUS endpoint and required 6 MiB transport chunk size.
- Same-browser resume, retry/backoff, pause, cancellation, and progress callbacks.
- Browser support, TypeScript types, pinned lockfile, MIT-compatible licensing, and an isolated replacement boundary.
- Owner-scoped private object paths and no overwrite/upsert behavior.
- Bounded logical objects with a content checksum verified again immediately before upload.

## Options considered

### Option A: `tus-js-client` 4.3.1

- Benefits: maintained TUS implementation with fingerprint persistence, previous-upload discovery, retry scheduling, pause/cancel primitives, and browser Blob support.
- Costs/risks: its persisted upload URL is sensitive operational metadata; application code must use a privacy-safe custom fingerprint and remove successful fingerprints.
- Environment/integration impact: browser bundle only; uses the existing public Supabase URL/publishable key and authenticated user JWT.
- Security/privacy/data impact: source bodies travel directly to private Storage. The client must never log the JWT, upload URL, object contents, raw source path, or user email.
- Reversibility: isolated behind `DirectImportUploader`; replaceable without changing manifest/API contracts.

### Option B: Hand-written TUS protocol client

- Benefits: smaller dependency surface and complete protocol control.
- Costs/risks: materially higher correctness and interoperability risk around resume URLs, offsets, retries, cancellation, and browser persistence.
- Environment/integration impact: same provider surface but substantially more custom protocol code.
- Security/privacy/data impact: custom persistence and header handling increase the chance of leaking sensitive upload metadata.
- Reversibility: not adopted.

## Decision

Use pinned `tus-js-client` 4.3.1 (MIT) for direct browser uploads. Upload one immutable logical object at a time, capped at 20 MiB, with a fixed 6 MiB TUS transport `chunkSize`. Use Supabase's direct Storage hostname for hosted projects, local API origin for local Supabase, retry delays of 0/3/5/10/20 seconds, no upsert, and a deterministic fingerprint derived only from the owner-scoped object path and synthetic-safe part checksum. Re-hash each selected source slice before upload and remove the fingerprint on success.

The UI remains fail-closed behind `NEXT_PUBLIC_IMPORT_UPLOAD_ENABLED` until cleanup, cross-owner, and target-environment verification gates are complete. The flag is not an authorization boundary; RLS and private Storage policies remain authoritative.

## Consequences

### Positive

- Supabase's supported resumable protocol is used without proxying source bytes through application servers.
- Pause/resume/retry state and progress can be exposed without persisting private source names.
- The uploader remains sequential and memory-bounded while the Step 3 concurrency policy stays at one.

### Negative and follow-up

- A persisted TUS URL can remain in browser storage after an interrupted upload until it expires; cancellation deletes server objects/metadata but provider-side unfinished upload cleanup also needs Step 3H evidence.
- ZIP entries require a separate bounded source adapter; the original ZIP is not uploaded as a retained source object.
- Existing `npm audit` findings in the Next/PostCSS and development-tool chains remain tracked separately; this dependency introduced no high or critical advisory at review time.

## Validation and revisit trigger

Require unit assertions for endpoint derivation, chunk size, privacy-safe fingerprints, source-change rejection, request-size paging, and cancellation. Require a generated-byte local Supabase probe covering API create, TUS upload, checksum verification/job completion, and deletion. Revisit if Supabase changes its required endpoint/chunk/lifetime rules, `tus-js-client` maintenance or licensing changes, browser persistence leaks sensitive metadata, or hosted interruption/resume evidence fails.
