# Health Tracking API

This Go service owns versioned HTTP boundaries, Supabase JWT/JWKS verification, authenticated user context, and future import/parser/application use cases.

## Local configuration

`.env.example` documents the required process variables, but the Go binary does not automatically load the file. Set values in the shell or deployment platform. The current JWT verifier uses public JWKS and does not require a Supabase secret/service-role key.

PowerShell example:

```powershell
$env:SUPABASE_URL = "http://127.0.0.1:54321"
$env:SUPABASE_JWT_ISSUER = "http://127.0.0.1:54321/auth/v1"
$env:SUPABASE_JWT_AUDIENCE = "authenticated"
go run ./cmd/api
```

## Commands

```text
gofmt -l .
go vet ./...
go test ./...
go run ./cmd/api
```

The public health endpoint is `http://localhost:8080/api/v1/health`. Protected routes must reject missing/invalid tokens and use the verified subject as the user boundary; repository methods must still filter by that user ID.

See [`../../docs/ENGINEERING_WORKFLOW.md`](../../docs/ENGINEERING_WORKFLOW.md) for API, migration, logging, and verification controls.
