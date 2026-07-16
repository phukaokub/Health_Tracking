package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/phukaokub/Health_Tracking/services/api/internal/auth"
	importdomain "github.com/phukaokub/Health_Tracking/services/api/internal/imports"
	"github.com/phukaokub/Health_Tracking/services/api/internal/supabase"
)

const importsBasePath = "/api/v1/imports"

type ImportService interface {
	CreateImport(context.Context, string, importdomain.ManifestCreateRequest) (importdomain.Snapshot, error)
	AppendManifestPage(context.Context, string, string, importdomain.ManifestPageRequest) (importdomain.Snapshot, error)
	GetImport(context.Context, string, string) (importdomain.Snapshot, error)
	CompleteImport(context.Context, string, string) (importdomain.Snapshot, error)
	DeleteImport(context.Context, string, string) (importdomain.Snapshot, error)
	CleanupImports(context.Context, string) (importdomain.CleanupResult, error)
}

type ImportHandler struct {
	service ImportService
}

func NewImportHandler(service ImportService) http.Handler {
	return &ImportHandler{service: service}
}

func (handler *ImportHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if _, ok := auth.UserFromContext(r.Context()); !ok {
		writeImportError(w, http.StatusUnauthorized, "missing_user_context")
		return
	}
	accessToken, ok := auth.AccessTokenFromContext(r.Context())
	if !ok {
		writeImportError(w, http.StatusUnauthorized, "missing_access_token")
		return
	}

	if r.URL.Path == importsBasePath || r.URL.Path == importsBasePath+"/" {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			writeImportError(w, http.StatusMethodNotAllowed, "method_not_allowed")
			return
		}
		handler.create(w, r, accessToken)
		return
	}

	relative := strings.TrimPrefix(r.URL.Path, importsBasePath+"/")
	segments := strings.Split(strings.Trim(relative, "/"), "/")
	if len(segments) == 1 && segments[0] == "cleanup" {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			writeImportError(w, http.StatusMethodNotAllowed, "method_not_allowed")
			return
		}
		handler.cleanup(w, r, accessToken)
		return
	}
	if len(segments) == 0 || !importdomain.IsUUID(segments[0]) {
		writeImportError(w, http.StatusNotFound, "not_found")
		return
	}
	importID := segments[0]
	if len(segments) == 1 {
		switch r.Method {
		case http.MethodGet:
			handler.get(w, r, accessToken, importID)
		case http.MethodDelete:
			handler.delete(w, r, accessToken, importID)
		default:
			w.Header().Set("Allow", http.MethodGet+", "+http.MethodDelete)
			writeImportError(w, http.StatusMethodNotAllowed, "method_not_allowed")
		}
		return
	}
	if len(segments) == 2 && segments[1] == "complete" {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			writeImportError(w, http.StatusMethodNotAllowed, "method_not_allowed")
			return
		}
		handler.complete(w, r, accessToken, importID)
		return
	}
	if len(segments) == 2 && segments[1] == "manifest-pages" {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			writeImportError(w, http.StatusMethodNotAllowed, "method_not_allowed")
			return
		}
		handler.appendManifestPage(w, r, accessToken, importID)
		return
	}
	writeImportError(w, http.StatusNotFound, "not_found")
}

func (handler *ImportHandler) cleanup(w http.ResponseWriter, r *http.Request, accessToken string) {
	result, err := handler.service.CleanupImports(r.Context(), accessToken)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeImportJSON(w, http.StatusOK, result)
}

func (handler *ImportHandler) appendManifestPage(w http.ResponseWriter, r *http.Request, accessToken, importID string) {
	r.Body = http.MaxBytesReader(w, r.Body, importdomain.MaxManifestBytes)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var request importdomain.ManifestPageRequest
	if err := decoder.Decode(&request); err != nil {
		writeDecodeError(w, err)
		return
	}
	if err := ensureJSONEOF(decoder); err != nil {
		writeDecodeError(w, err)
		return
	}
	if err := request.Validate(); err != nil {
		writeImportError(w, http.StatusBadRequest, "invalid_manifest_page")
		return
	}
	snapshot, err := handler.service.AppendManifestPage(r.Context(), accessToken, importID, request)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeImportJSON(w, http.StatusOK, snapshot)
}

func (handler *ImportHandler) create(w http.ResponseWriter, r *http.Request, accessToken string) {
	r.Body = http.MaxBytesReader(w, r.Body, importdomain.MaxManifestBytes)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var request importdomain.ManifestCreateRequest
	if err := decoder.Decode(&request); err != nil {
		writeDecodeError(w, err)
		return
	}
	if err := ensureJSONEOF(decoder); err != nil {
		writeDecodeError(w, err)
		return
	}
	if err := request.Validate(); err != nil {
		writeImportError(w, http.StatusBadRequest, "invalid_manifest")
		return
	}
	snapshot, err := handler.service.CreateImport(r.Context(), accessToken, request)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeImportJSON(w, http.StatusCreated, snapshot)
}

func (handler *ImportHandler) get(w http.ResponseWriter, r *http.Request, accessToken, importID string) {
	snapshot, err := handler.service.GetImport(r.Context(), accessToken, importID)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeImportJSON(w, http.StatusOK, snapshot)
}

func (handler *ImportHandler) complete(w http.ResponseWriter, r *http.Request, accessToken, importID string) {
	snapshot, err := handler.service.CompleteImport(r.Context(), accessToken, importID)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeImportJSON(w, http.StatusOK, snapshot)
}

func (handler *ImportHandler) delete(w http.ResponseWriter, r *http.Request, accessToken, importID string) {
	snapshot, err := handler.service.DeleteImport(r.Context(), accessToken, importID)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeImportJSON(w, http.StatusOK, snapshot)
}

func ensureJSONEOF(decoder *json.Decoder) error {
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		if err == nil {
			return errors.New("multiple JSON values")
		}
		return err
	}
	return nil
}

func writeDecodeError(w http.ResponseWriter, err error) {
	var maxBytesError *http.MaxBytesError
	if errors.As(err, &maxBytesError) {
		writeImportError(w, http.StatusRequestEntityTooLarge, "manifest_too_large")
		return
	}
	writeImportError(w, http.StatusBadRequest, "invalid_json")
}

func writeServiceError(w http.ResponseWriter, err error) {
	var apiError *supabase.APIError
	if errors.As(err, &apiError) {
		switch {
		case apiError.Status == http.StatusUnauthorized || apiError.Status == http.StatusForbidden:
			writeImportError(w, http.StatusForbidden, "import_forbidden")
		case apiError.Status == http.StatusNotFound || apiError.Code == "P0002":
			writeImportError(w, http.StatusNotFound, "import_not_found")
		case apiError.Status == http.StatusConflict || apiError.Code == "HT409":
			writeImportError(w, http.StatusConflict, "import_conflict")
		case apiError.Status >= 400 && apiError.Status < 500:
			writeImportError(w, http.StatusBadRequest, "import_rejected")
		default:
			writeImportError(w, http.StatusBadGateway, "supabase_unavailable")
		}
		return
	}
	writeImportError(w, http.StatusBadGateway, "supabase_unavailable")
}

func writeImportError(w http.ResponseWriter, status int, code string) {
	writeImportJSON(w, status, map[string]string{"error": code})
}

func writeImportJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
