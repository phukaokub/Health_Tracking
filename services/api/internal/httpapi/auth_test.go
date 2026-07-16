package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/phukaokub/Health_Tracking/services/api/internal/auth"
)

type stubVerifier struct {
	user auth.User
	err  error
}

func (s stubVerifier) Verify(token string) (auth.User, error) { return s.user, s.err }

func TestAuthRequireUserAcceptsBearerToken(t *testing.T) {
	handler := RequireUser(stubVerifier{user: auth.User{ID: "user-1"}}, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth.UserFromContext(r.Context())
		if !ok || user.ID != "user-1" {
			t.Fatalf("expected user in context, got %#v", user)
		}
		accessToken, ok := auth.AccessTokenFromContext(r.Context())
		if !ok || accessToken != "token" {
			t.Fatalf("expected verified token in separate context value")
		}
		w.WriteHeader(http.StatusNoContent)
	}))

	req := httptest.NewRequest(http.MethodGet, "/private", nil)
	req.Header.Set("Authorization", "Bearer token")
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	if res.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", res.Code)
	}
}

func TestAuthRequireUserRejectsMissingBearerToken(t *testing.T) {
	handler := RequireUser(stubVerifier{}, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { t.Fatal("next should not run") }))
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, httptest.NewRequest(http.MethodGet, "/private", nil))
	if res.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", res.Code)
	}
}
