package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strconv"

	"github.com/phukaokub/Health_Tracking/services/api/internal/auth"
	"github.com/phukaokub/Health_Tracking/services/api/internal/summary"
	"github.com/phukaokub/Health_Tracking/services/api/internal/supabase"
)

type SummaryService interface {
	GetSummary(context.Context, string, int) (summary.Snapshot, error)
}

type SummaryHandler struct {
	service SummaryService
}

func NewSummaryHandler(service SummaryService) http.Handler {
	return &SummaryHandler{service: service}
}

func (handler *SummaryHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		writeSummaryError(w, http.StatusMethodNotAllowed, "method_not_allowed")
		return
	}
	if _, ok := auth.UserFromContext(r.Context()); !ok {
		writeSummaryError(w, http.StatusUnauthorized, "missing_user_context")
		return
	}
	accessToken, ok := auth.AccessTokenFromContext(r.Context())
	if !ok {
		writeSummaryError(w, http.StatusUnauthorized, "missing_access_token")
		return
	}

	windowDays := 7
	if raw := r.URL.Query().Get("window"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || !summary.ValidWindow(parsed) {
			writeSummaryError(w, http.StatusBadRequest, "summary_window_invalid")
			return
		}
		windowDays = parsed
	}
	snapshot, err := handler.service.GetSummary(r.Context(), accessToken, windowDays)
	if err != nil {
		writeSummaryServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, snapshot)
}

func writeSummaryServiceError(w http.ResponseWriter, err error) {
	if errors.Is(err, summary.ErrInvalidWindow) {
		writeSummaryError(w, http.StatusBadRequest, "summary_window_invalid")
		return
	}
	var apiError *supabase.APIError
	if errors.As(err, &apiError) {
		switch {
		case apiError.Status == http.StatusUnauthorized || apiError.Status == http.StatusForbidden:
			writeSummaryError(w, http.StatusForbidden, "summary_forbidden")
		case apiError.Status == http.StatusBadRequest:
			writeSummaryError(w, http.StatusBadRequest, "summary_rejected")
		default:
			writeSummaryError(w, http.StatusBadGateway, "summary_unavailable")
		}
		return
	}
	writeSummaryError(w, http.StatusBadGateway, "summary_unavailable")
}

func writeSummaryError(w http.ResponseWriter, status int, code string) {
	writeJSON(w, status, map[string]string{"error": code})
}
