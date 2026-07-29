# Health Tracking API

This Go service owns versioned HTTP boundaries, Supabase JWT/JWKS verification, authenticated user context, and future import/parser/application use cases.

## Local configuration

`.env.example` documents the required process variables, but the Go binary does not automatically load the file. The normal local command is run from the repository root; it starts local Supabase, derives the local publishable key without displaying it, sets the API process environment, and starts Go:

```powershell
go run ./cmd/dev
```

`./start-local.cmd` runs the same command on Windows. Before the first run, copy `../../.env.local.example` to `../../.env.local` and set the local Google OAuth client ID and secret once; the file is ignored by Git. Use `go run ./cmd/dev -check-only` to confirm local Supabase and the API environment without starting the server. The JWT verifier uses public JWKS. Foreground import persistence forwards the verified user JWT with the Supabase publishable key so database and Storage RLS remain authoritative; it does not use a Supabase secret/service-role key.

PowerShell example:

```powershell
$env:SUPABASE_URL = "http://127.0.0.1:54321"
$env:SUPABASE_PUBLISHABLE_KEY = "<publishable value from npx supabase status>"
$env:SUPABASE_JWT_ISSUER = "http://127.0.0.1:54321/auth/v1"
$env:SUPABASE_JWT_AUDIENCE = "authenticated"
$env:WEB_ORIGIN = "http://localhost:3000"
go run ./cmd/api
```

## Commands

```text
gofmt -l .
go vet ./...
go test ./...
go run ./cmd/api
```

The public health endpoint is `http://localhost:8080/api/v1/health`. Protected routes reject missing/invalid tokens. Import routes never accept an owner ID; the forwarded verified token supplies `auth.uid()` and owner-scoped RLS remains the persistence boundary.

## Manual staging worker trigger

The internal `POST /api/v1/worker/trigger` route is protected by the server-only
`X-Worker-Trigger` value and authenticates the dedicated Supabase worker
identity. `synthetic_benchmark` and `synthetic_multifile_benchmark` generate
only synthetic Huawei-shaped JSON and measure deterministic recovery,
time, and heap use. `process_import` claims at most one server-selected job,
streams only its lease-authorized private Storage parts, and persists typed
canonical batches. `cleanup_sources` removes only terminal raw sources whose
24-hour recovery deadline has elapsed.

Real-import and cleanup modes require `WORKER_PROCESS_IMPORT_ENABLED=true`.
The staging scripts rotate the trigger secret, enable the gate for one reviewed
manual drill, and restore the gate to `false` in a `finally` path. The stable
staging deployment must remain default-off; no production worker is configured.

Example request (substitute the secret locally; never paste it into source or
logs):

```powershell
$headers = @{ "X-Worker-Trigger" = $env:WORKER_TRIGGER_SECRET }
Invoke-WebRequest -Method Post -Uri "http://localhost:8080/api/v1/worker/trigger" -Headers $headers -ContentType "application/json" -Body '{"mode":"synthetic_benchmark","target_bytes":75497472}'
```

Repository operators can use
`../../scripts/Invoke-StagingWorkerBenchmark.ps1` for the generated 72 MiB and
330 MiB capacity gates and `../../scripts/Invoke-StagingWorkerRuntime.ps1` for
the bounded real-import or recovery-expired cleanup drills. Their output is
limited to counts, stable warning codes, timing, and memory; credentials,
owner identifiers, object paths, and source content are excluded.

See [`../../docs/ENGINEERING_WORKFLOW.md`](../../docs/ENGINEERING_WORKFLOW.md) for API, migration, logging, and verification controls.
