package httpapi

import (
	"net/http"
	"strings"

	"github.com/phukaokub/Health_Tracking/services/api/internal/auth"
)

type TokenVerifier interface {
	Verify(token string) (auth.User, error)
}

func RequireUser(verifier TokenVerifier, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		token, ok := strings.CutPrefix(header, "Bearer ")
		if !ok || strings.TrimSpace(token) == "" {
			http.Error(w, `{"error":"missing_bearer_token"}`, http.StatusUnauthorized)
			return
		}
		user, err := verifier.Verify(strings.TrimSpace(token))
		if err != nil {
			http.Error(w, `{"error":"invalid_token"}`, http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r.WithContext(auth.WithUser(r.Context(), user)))
	})
}
