# Health Tracking API

This Go service owns versioned HTTP boundaries, Supabase JWT/JWKS verification, authenticated user context, and future import/parser/application use cases.

## Local configuration

`.env.example` documents the required process variables, but the Go binary does not automatically load the file. Set values in the shell or deployment platform. The JWT verifier uses public JWKS. Foreground import persistence forwards the verified user JWT with the Supabase publishable key so database and Storage RLS remain authoritative; it does not use a Supabase secret/service-role key.

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

See [`../../docs/ENGINEERING_WORKFLOW.md`](../../docs/ENGINEERING_WORKFLOW.md) for API, migration, logging, and verification controls.
