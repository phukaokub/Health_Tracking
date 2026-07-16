package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/phukaokub/Health_Tracking/services/api/internal/auth"
	"github.com/phukaokub/Health_Tracking/services/api/internal/httpapi"
	"github.com/phukaokub/Health_Tracking/services/api/internal/supabase"
)

const version = "0.1.0"

type healthResponse struct {
	Status    string `json:"status"`
	Service   string `json:"service"`
	Version   string `json:"version"`
	RequestID string `json:"request_id"`
	Timestamp string `json:"timestamp"`
}

type requestIDContextKey struct{}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/health", healthHandler)
	verifier, err := newVerifier(context.Background())
	if err != nil {
		log.Fatalf("initialize auth verifier: %v", err)
	}
	mux.Handle("/api/v1/me", httpapi.RequireUser(verifier, http.HandlerFunc(currentUserHandler)))
	importClient, err := newImportClient()
	if err != nil {
		log.Fatalf("initialize import persistence: %v", err)
	}
	importHandler := httpapi.RequireUser(verifier, httpapi.NewImportHandler(importClient))
	mux.Handle("/api/v1/imports", importHandler)
	mux.Handle("/api/v1/imports/", importHandler)
	webOrigin := os.Getenv("WEB_ORIGIN")
	if webOrigin == "" {
		webOrigin = "http://localhost:3000"
	}

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           requestID(cors(webOrigin, mux)),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	log.Printf("api listening on %s", server.Addr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}

func newImportClient() (*supabase.Client, error) {
	baseURL := strings.TrimRight(os.Getenv("SUPABASE_URL"), "/")
	if baseURL == "" {
		baseURL = "http://127.0.0.1:54321"
	}
	return supabase.NewClient(baseURL, os.Getenv("SUPABASE_PUBLISHABLE_KEY"), nil)
}

func newVerifier(ctx context.Context) (*auth.Verifier, error) {
	baseURL := strings.TrimRight(os.Getenv("SUPABASE_URL"), "/")
	if baseURL == "" {
		baseURL = "http://127.0.0.1:54321"
	}
	issuer := os.Getenv("SUPABASE_JWT_ISSUER")
	if issuer == "" {
		issuer = baseURL + "/auth/v1"
	}
	audience := os.Getenv("SUPABASE_JWT_AUDIENCE")
	if audience == "" {
		audience = "authenticated"
	}
	jwks, err := auth.FetchJWKS(ctx, issuer+"/.well-known/jwks.json")
	if err != nil {
		return nil, err
	}
	return auth.NewVerifier(issuer, audience, jwks)
}

func currentUserHandler(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing_user_context"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"user_id": user.ID})
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method_not_allowed"})
		return
	}

	writeJSON(w, http.StatusOK, healthResponse{
		Status:    "ok",
		Service:   "health-tracking-api",
		Version:   version,
		RequestID: requestIDFromContext(r),
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
	})
}

func requestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-ID")
		if id == "" {
			id = newRequestID()
		}
		w.Header().Set("X-Request-ID", id)
		next.ServeHTTP(w, r.WithContext(withRequestID(r.Context(), id)))
	})
}

func cors(allowedOrigin string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && origin == allowedOrigin {
			w.Header().Set("Access-Control-Allow-Origin", allowedOrigin)
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Request-ID")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
			w.Header().Set("Vary", "Origin")
		}
		if r.Method == http.MethodOptions {
			if origin != allowedOrigin {
				writeJSON(w, http.StatusForbidden, map[string]string{"error": "origin_not_allowed"})
				return
			}
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func newRequestID() string {
	var bytes [16]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "request-unknown"
	}
	return hex.EncodeToString(bytes[:])
}

func withRequestID(ctx context.Context, id string) context.Context {
	return context.WithValue(ctx, requestIDContextKey{}, id)
}

func requestIDFromContext(r *http.Request) string {
	id, ok := r.Context().Value(requestIDContextKey{}).(string)
	if !ok || id == "" {
		return "request-unknown"
	}
	return id
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
