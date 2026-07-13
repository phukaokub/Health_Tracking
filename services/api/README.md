# Health Tracking API

The API is a Go service that will own authentication-aware use cases, parsing jobs, and Postgres/Storage adapters. Step 0 contains only the versioned health endpoint and request ID boundary.

Run locally from this directory:

```text
go test ./...
go run ./cmd/api
```

Then request `http://localhost:8080/api/v1/health`.

