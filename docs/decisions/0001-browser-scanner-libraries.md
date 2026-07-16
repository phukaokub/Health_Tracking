# ADR 0001: Browser scanner ZIP and incremental-hash libraries

- Status: accepted
- Date: 2026-07-16
- Decision owners: repository maintainer with Codex implementation support
- Related milestone/change/PR: Step 3 / 3D / `codex/step-3-import-scanner`
- Supersedes / superseded by: none

## Context

The Step 3 scanner must classify an export in a browser Worker, hash file content incrementally, and later inspect ZIP files without sending source content through an application server. `crypto.subtle.digest()` only accepts a complete buffer, so it cannot meet the no-whole-export-buffer rule. ZIP support also needs streaming input, path validation, bounded entry counts, and a later cancellation/recovery implementation.

## Decision drivers

- Browser and Worker support with TypeScript types.
- Incremental SHA-256 instead of a whole-file buffer.
- Streaming ZIP input and a small, maintained dependency surface.
- MIT-compatible licensing, pinned versions, synthetic tests, and a replacement path.
- No source content, local path, JWT, or upload URL reaches telemetry, logs, or an API.

## Options considered

### Option A: `fflate` 0.8.3 plus `hash-wasm` 4.12.0

- Benefits: `fflate` offers ESM ZIP streaming and `hash-wasm` exposes incremental SHA-256; both are MIT-licensed and work in browser-oriented code.
- Costs/risks: ZIP safety is application-owned, so the scanner must still enforce traversal, entry, size, and expansion-ratio limits. WebAssembly initialization is asynchronous.
- Environment/integration impact: browser bundle only; no new environment variable, hosted provider, or credential.
- Security/privacy/data impact: hashes and classification stay in the Worker; raw content is not posted to an API.
- Reversibility: isolated under `src/lib/imports`; can be replaced before upload is enabled.

### Option B: Web Crypto plus a native browser compression API

- Benefits: fewer dependencies.
- Costs/risks: no incremental Web Crypto digest and no native ZIP parser, so it violates the streaming/hash requirement.
- Environment/integration impact: none.
- Security/privacy/data impact: would encourage whole-file buffering.
- Reversibility: not adopted.

## Decision

Use pinned `fflate` 0.8.3 for bounded local ZIP review and `hash-wasm` 4.12.0 for incremental SHA-256 in the Worker. Use `tsx` 4.21.0 only as a development test runner for synthetic TypeScript unit tests. ZIP review enforces traversal, entry-count, metadata-size, total-size, and expansion-ratio controls. Upload remains gated until the explicit cancellation/recovery UX and direct Storage/TUS integration are complete.

## Consequences

### Positive

- Directory scans hash chunks in a Worker rather than collecting an export in a single application buffer.
- The ZIP library has a synthetic chunked-stream test before it is used for user input.
- The scanner policy and dependencies have a dedicated decision record and CI test gate.

### Negative and follow-up

- `npm audit --omit=dev` reports two existing moderate findings in the pinned Next/PostCSS dependency chain; no advisory was reported for the newly added scanner libraries. Review a compatible Next update separately rather than force-upgrading in this scanner change.
- The initial UI intentionally has no upload action. Add explicit cancellation UX and more archive-corruption/unsupported-compression fixtures before enabling upload.
- Add package license/security review to the Step 8 dependency gate and re-evaluate these versions on upgrade.

## Validation and revisit trigger

The scanner policy, chunked `fflate` ZIP spike, and production build must pass locally and in CI. Revisit if browser Worker bundling fails, a supported Huawei archive uses an unsupported ZIP compression method, package maintenance/security status changes, or a streaming memory test exceeds the documented limit.
