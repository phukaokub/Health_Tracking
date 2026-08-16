package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/phukaokub/Health_Tracking/services/api/internal/auth"
	"github.com/phukaokub/Health_Tracking/services/api/internal/summary"
)

type fakeSummaryService struct {
	window int
}

func (service *fakeSummaryService) GetSummary(_ context.Context, _ string, window int) (summary.Snapshot, error) {
	service.window = window
	return summary.Snapshot{WindowDays: window, Timezone: "UTC", Metrics: []summary.Metric{}}, nil
}

func TestSummaryHandlerRequiresVerifiedUserContext(t *testing.T) {
	handler := NewSummaryHandler(&fakeSummaryService{})
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/summary?window=7", nil))
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected unauthorized response, got %d", response.Code)
	}
}

func TestSummaryHandlerAllowListsWindowsAndPassesAccessToken(t *testing.T) {
	service := &fakeSummaryService{}
	handler := NewSummaryHandler(service)
	request := httptest.NewRequest(http.MethodGet, "/api/v1/summary?window=28", nil)
	ctx := auth.WithUser(request.Context(), auth.User{ID: "synthetic-user"})
	ctx = auth.WithAccessToken(ctx, "synthetic-token")
	request = request.WithContext(ctx)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK || service.window != 28 {
		t.Fatalf("unexpected response: status=%d window=%d", response.Code, service.window)
	}
	var payload summary.Snapshot
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload.WindowDays != 28 {
		t.Fatalf("unexpected window in response: %#v", payload)
	}
}

func TestSummaryHandlerRejectsUnboundedWindow(t *testing.T) {
	service := &fakeSummaryService{}
	handler := NewSummaryHandler(service)
	request := httptest.NewRequest(http.MethodGet, "/api/v1/summary?window=14", nil)
	ctx := auth.WithUser(request.Context(), auth.User{ID: "synthetic-user"})
	ctx = auth.WithAccessToken(ctx, "synthetic-token")
	request = request.WithContext(ctx)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusBadRequest || service.window != 0 {
		t.Fatalf("unbounded window was accepted: status=%d window=%d", response.Code, service.window)
	}
}
