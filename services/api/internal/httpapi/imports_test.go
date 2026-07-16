package httpapi

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/phukaokub/Health_Tracking/services/api/internal/auth"
	importdomain "github.com/phukaokub/Health_Tracking/services/api/internal/imports"
	"github.com/phukaokub/Health_Tracking/services/api/internal/supabase"
)

const validImportID = "10000000-0000-4000-8000-000000000001"

type fakeImportService struct {
	createRequest importdomain.ManifestCreateRequest
	accessToken   string
	method        string
	err           error
}

func (service *fakeImportService) CreateImport(_ context.Context, token string, request importdomain.ManifestCreateRequest) (importdomain.Snapshot, error) {
	service.method, service.accessToken, service.createRequest = "create", token, request
	return importdomain.Snapshot{ID: validImportID, State: importdomain.ImportStateUploading}, service.err
}
func (service *fakeImportService) GetImport(_ context.Context, token, _ string) (importdomain.Snapshot, error) {
	service.method, service.accessToken = "get", token
	return importdomain.Snapshot{ID: validImportID, State: importdomain.ImportStateUploading}, service.err
}
func (service *fakeImportService) AppendManifestPage(_ context.Context, token, _ string, _ importdomain.ManifestPageRequest) (importdomain.Snapshot, error) {
	service.method, service.accessToken = "append-page", token
	return importdomain.Snapshot{ID: validImportID, State: importdomain.ImportStateUploading}, service.err
}
func (service *fakeImportService) CompleteImport(_ context.Context, token, _ string) (importdomain.Snapshot, error) {
	service.method, service.accessToken = "complete", token
	return importdomain.Snapshot{ID: validImportID, State: importdomain.ImportStateQueued}, service.err
}
func (service *fakeImportService) DeleteImport(_ context.Context, token, _ string) (importdomain.Snapshot, error) {
	service.method, service.accessToken = "delete", token
	return importdomain.Snapshot{ID: validImportID, State: importdomain.ImportStateDeleted}, service.err
}

func authenticatedImportRequest(method, target, body string) *http.Request {
	request := httptest.NewRequest(method, target, strings.NewReader(body))
	ctx := auth.WithUser(request.Context(), auth.User{ID: "00000000-0000-4000-8000-000000000001"})
	ctx = auth.WithAccessToken(ctx, "verified-user-token")
	return request.WithContext(ctx)
}

func TestImportHandlerCreatesBoundedMetadataManifest(t *testing.T) {
	service := &fakeImportService{}
	handler := NewImportHandler(service)
	body := `{
		"manifest_version":1,
		"source_kind":"directory",
		"client_idempotency_key":"30000000-0000-4000-8000-000000000001",
		"timezone_candidate":"Asia/Bangkok",
		"total_file_count":1,
		"total_logical_bytes":1,
		"page_content_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"files":[{
			"client_file_id":"40000000-0000-4000-8000-000000000001",
			"source_reference_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
			"source_family":"synthetic-json",
			"content_kind":"application/json",
			"logical_bytes":1,
			"content_sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
			"inclusion_state":"planned",
			"parts":[{"part_index":0,"byte_offset":0,"byte_length":1,"content_sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}]
		}]
	}`
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, authenticatedImportRequest(http.MethodPost, importsBasePath, body))
	if response.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", response.Code, response.Body.String())
	}
	if service.method != "create" || service.accessToken != "verified-user-token" {
		t.Fatalf("expected create with forwarded verified token, got %q %q", service.method, service.accessToken)
	}
	if service.createRequest.TotalLogicalBytes != 1 || len(service.createRequest.Files) != 1 {
		t.Fatalf("manifest was not decoded: %#v", service.createRequest)
	}
}

func TestImportHandlerRejectsUnknownOrOversizedManifest(t *testing.T) {
	handler := NewImportHandler(&fakeImportService{})
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, authenticatedImportRequest(http.MethodPost, importsBasePath, `{"unknown":true}`))
	if response.Code != http.StatusBadRequest {
		t.Fatalf("expected unknown-field 400, got %d", response.Code)
	}

	response = httptest.NewRecorder()
	oversized := `{"padding":"` + strings.Repeat("x", importdomain.MaxManifestBytes) + `"}`
	handler.ServeHTTP(response, authenticatedImportRequest(http.MethodPost, importsBasePath, oversized))
	if response.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("expected 413, got %d", response.Code)
	}
}

func TestImportHandlerRoutesStatusCompletionAndDeletion(t *testing.T) {
	service := &fakeImportService{}
	handler := NewImportHandler(service)
	for _, test := range []struct {
		method string
		path   string
		want   string
	}{
		{http.MethodGet, importsBasePath + "/" + validImportID, "get"},
		{http.MethodPost, importsBasePath + "/" + validImportID + "/complete", "complete"},
		{http.MethodDelete, importsBasePath + "/" + validImportID, "delete"},
	} {
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, authenticatedImportRequest(test.method, test.path, ""))
		if response.Code != http.StatusOK || service.method != test.want {
			t.Fatalf("%s %s: expected %s/200, got %s/%d", test.method, test.path, test.want, service.method, response.Code)
		}
	}
}

func TestImportHandlerAppendsManifestPage(t *testing.T) {
	service := &fakeImportService{}
	body := `{
		"page_index":1,
		"page_content_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"files":[{
			"client_file_id":"40000000-0000-4000-8000-000000000002",
			"source_reference_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
			"source_family":"synthetic-json",
			"content_kind":"application/json",
			"logical_bytes":1,
			"content_sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
			"inclusion_state":"planned",
			"parts":[{"part_index":0,"byte_offset":0,"byte_length":1,"content_sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}]
		}]
	}`
	response := httptest.NewRecorder()
	NewImportHandler(service).ServeHTTP(
		response,
		authenticatedImportRequest(http.MethodPost, importsBasePath+"/"+validImportID+"/manifest-pages", body),
	)
	if response.Code != http.StatusOK || service.method != "append-page" || service.accessToken != "verified-user-token" {
		t.Fatalf("expected manifest page call, got method=%q token=%q status=%d body=%s", service.method, service.accessToken, response.Code, response.Body.String())
	}
}

func TestImportHandlerMapsOwnerScopedNotFound(t *testing.T) {
	service := &fakeImportService{err: &supabase.APIError{Status: http.StatusNotFound, Code: "P0002"}}
	response := httptest.NewRecorder()
	NewImportHandler(service).ServeHTTP(response, authenticatedImportRequest(http.MethodGet, importsBasePath+"/"+validImportID, ""))
	if response.Code != http.StatusNotFound || !strings.Contains(response.Body.String(), "import_not_found") {
		t.Fatalf("expected redacted 404, got %d: %s", response.Code, response.Body.String())
	}
	if strings.Contains(response.Body.String(), "P0002") {
		t.Fatal("upstream database code must not be exposed")
	}
}

func TestImportHandlerMapsIdempotencyConflict(t *testing.T) {
	service := &fakeImportService{err: &supabase.APIError{Status: http.StatusBadRequest, Code: "HT409"}}
	response := httptest.NewRecorder()
	NewImportHandler(service).ServeHTTP(response, authenticatedImportRequest(http.MethodGet, importsBasePath+"/"+validImportID, ""))
	if response.Code != http.StatusConflict || !strings.Contains(response.Body.String(), "import_conflict") {
		t.Fatalf("expected redacted 409, got %d: %s", response.Code, response.Body.String())
	}
}

func TestImportHandlerRejectsMissingContext(t *testing.T) {
	response := httptest.NewRecorder()
	NewImportHandler(&fakeImportService{err: errors.New("must not run")}).ServeHTTP(
		response,
		httptest.NewRequest(http.MethodGet, importsBasePath+"/"+validImportID, nil),
	)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", response.Code)
	}
}
