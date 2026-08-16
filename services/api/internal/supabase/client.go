package supabase

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/phukaokub/Health_Tracking/services/api/internal/imports"
	"github.com/phukaokub/Health_Tracking/services/api/internal/normalization"
	"github.com/phukaokub/Health_Tracking/services/api/internal/summary"
)

const importBucket = "health-imports"

type Client struct {
	baseURL        string
	publishableKey string
	httpClient     *http.Client
	workerClient   *http.Client
}

type APIError struct {
	Status int
	Code   string
}

type WorkerIdentity struct {
	ImportWorker bool
	Subject      string
	accessToken  string
}

// WorkerLease and WorkerSource are intentionally metadata-only. Source bytes
// are streamed directly from private Storage and never become API responses or
// logs.
type WorkerLease struct {
	JobID           string `json:"job_id"`
	ImportID        string `json:"import_id"`
	UserID          string `json:"user_id"`
	LeaseGeneration string `json:"lease_generation"`
	Attempt         int    `json:"attempt_count"`
}

type WorkerSourcePart struct {
	PartIndex     int    `json:"part_index"`
	ByteLength    int64  `json:"byte_length"`
	ContentSHA256 string `json:"content_sha256"`
	ObjectPath    string `json:"object_path"`
}

type WorkerSourceFile struct {
	ID                string             `json:"id"`
	LogicalBytes      int64              `json:"logical_bytes"`
	ContentSHA256     string             `json:"content_sha256"`
	SourceFamily      string             `json:"source_family"`
	ContentKind       string             `json:"content_kind"`
	TimezoneCandidate string             `json:"timezone_candidate"`
	Parts             []WorkerSourcePart `json:"parts"`
}

type WorkerCleanupCandidate struct {
	ImportID    string   `json:"import_id"`
	ObjectPaths []string `json:"object_paths"`
}

func (err *APIError) Error() string {
	return fmt.Sprintf("supabase request failed: status=%d code=%s", err.Status, err.Code)
}

func NewClient(baseURL, publishableKey string, httpClient *http.Client) (*Client, error) {
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if baseURL == "" {
		return nil, errors.New("supabase URL is required")
	}
	parsed, err := url.Parse(baseURL)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return nil, errors.New("supabase URL must be an absolute HTTP(S) URL")
	}
	if strings.TrimSpace(publishableKey) == "" {
		return nil, errors.New("SUPABASE_PUBLISHABLE_KEY is required")
	}
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 15 * time.Second}
	}
	workerClient := *httpClient
	workerClient.Timeout = 240 * time.Second
	return &Client{
		baseURL: baseURL, publishableKey: publishableKey,
		httpClient: httpClient, workerClient: &workerClient,
	}, nil
}

func (client *Client) CreateImport(ctx context.Context, accessToken string, request imports.ManifestCreateRequest) (imports.Snapshot, error) {
	return client.rpc(ctx, accessToken, "create_import_manifest", map[string]any{"p_manifest": request})
}

func (client *Client) GetImport(ctx context.Context, accessToken, importID string) (imports.Snapshot, error) {
	return client.rpc(ctx, accessToken, "import_api_snapshot", map[string]string{"p_import_id": importID})
}

func (client *Client) AppendManifestPage(ctx context.Context, accessToken, importID string, request imports.ManifestPageRequest) (imports.Snapshot, error) {
	return client.rpc(ctx, accessToken, "append_import_manifest_page", map[string]any{
		"p_import_id": importID,
		"p_page":      request,
	})
}

func (client *Client) CompleteImport(ctx context.Context, accessToken, importID string) (imports.Snapshot, error) {
	return client.rpc(ctx, accessToken, "complete_import", map[string]string{"p_import_id": importID})
}

func (client *Client) DeleteImport(ctx context.Context, accessToken, importID string) (imports.Snapshot, error) {
	var pending struct {
		ObjectPaths []string `json:"object_paths"`
	}
	if err := client.requestJSON(ctx, accessToken, http.MethodPost, "/rest/v1/rpc/begin_import_delete", map[string]string{"p_import_id": importID}, &pending); err != nil {
		return imports.Snapshot{}, err
	}
	for start := 0; start < len(pending.ObjectPaths); start += 1000 {
		end := start + 1000
		if end > len(pending.ObjectPaths) {
			end = len(pending.ObjectPaths)
		}
		if err := client.deleteObjects(ctx, accessToken, pending.ObjectPaths[start:end]); err != nil {
			return imports.Snapshot{}, err
		}
	}
	return client.rpc(ctx, accessToken, "finish_import_delete", map[string]string{"p_import_id": importID})
}

func (client *Client) CleanupImports(ctx context.Context, accessToken string) (imports.CleanupResult, error) {
	var expired []struct {
		ImportID string `json:"import_id"`
	}
	if err := client.requestJSON(ctx, accessToken, http.MethodPost, "/rest/v1/rpc/list_expired_imports", map[string]int{"p_limit": 25}, &expired); err != nil {
		return imports.CleanupResult{}, err
	}
	result := imports.CleanupResult{}
	for _, item := range expired {
		if _, err := client.DeleteImport(ctx, accessToken, item.ImportID); err != nil {
			var apiError *APIError
			if errors.As(err, &apiError) && apiError.Status == http.StatusNotFound {
				continue
			}
			return result, err
		}
		result.DeletedCount++
	}
	return result, nil
}

func (client *Client) GetSummary(ctx context.Context, accessToken string, windowDays int) (summary.Snapshot, error) {
	if !summary.ValidWindow(windowDays) {
		return summary.Snapshot{}, summary.ErrInvalidWindow
	}
	var snapshot summary.Snapshot
	if err := client.requestJSON(ctx, accessToken, http.MethodPost, "/rest/v1/rpc/summary_api_snapshot", map[string]int{"p_window_days": windowDays}, &snapshot); err != nil {
		return summary.Snapshot{}, err
	}
	return snapshot, nil
}

// AuthenticateWorker obtains a short-lived Auth token for the dedicated
// staging worker identity. The password never leaves this request and the
// response is reduced to the app_metadata claim needed by the trigger.
func (client *Client) AuthenticateWorker(ctx context.Context, email, password string) (WorkerIdentity, error) {
	if strings.TrimSpace(email) == "" || strings.TrimSpace(password) == "" {
		return WorkerIdentity{}, errors.New("worker_configuration_invalid")
	}
	var response struct {
		AccessToken string `json:"access_token"`
		User        struct {
			ID          string         `json:"id"`
			AppMetadata map[string]any `json:"app_metadata"`
		} `json:"user"`
	}
	if err := client.requestJSON(ctx, client.publishableKey, http.MethodPost, "/auth/v1/token?grant_type=password", map[string]string{
		"email":    email,
		"password": password,
	}, &response); err != nil {
		return WorkerIdentity{}, err
	}
	if response.AccessToken == "" {
		return WorkerIdentity{}, errors.New("worker_configuration_invalid")
	}
	claim, ok := response.User.AppMetadata["import_worker"].(bool)
	if !ok || !claim {
		return WorkerIdentity{}, errors.New("worker_configuration_invalid")
	}
	if response.User.ID == "" {
		return WorkerIdentity{}, errors.New("worker_configuration_invalid")
	}
	return WorkerIdentity{ImportWorker: true, Subject: response.User.ID, accessToken: response.AccessToken}, nil
}

// ClaimWorkerImport returns one server-selected lease. Callers cannot select an
// owner, import, or Storage path.
func (client *Client) ClaimWorkerImport(ctx context.Context, identity WorkerIdentity, parserVersion string, leaseSeconds int) (*WorkerLease, error) {
	if !identity.ImportWorker || identity.accessToken == "" || identity.Subject == "" {
		return nil, errors.New("worker_configuration_invalid")
	}
	var rows []WorkerLease
	if err := client.requestWorkerJSON(ctx, identity.accessToken, http.MethodPost, "/rest/v1/rpc/worker_claim_import_job", map[string]any{"p_parser_version": parserVersion, "p_lease_seconds": leaseSeconds}, &rows); err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, nil
	}
	return &rows[0], nil
}

func (client *Client) WorkerImportSource(ctx context.Context, identity WorkerIdentity, lease WorkerLease) ([]WorkerSourceFile, error) {
	var files []WorkerSourceFile
	if err := client.requestWorkerJSON(ctx, identity.accessToken, http.MethodPost, "/rest/v1/rpc/worker_import_source", map[string]string{"p_job_id": lease.JobID, "p_lease_generation": lease.LeaseGeneration}, &files); err != nil {
		return nil, err
	}
	return files, nil
}

func (client *Client) RenewWorkerImport(ctx context.Context, identity WorkerIdentity, lease WorkerLease, leaseSeconds int) (bool, error) {
	var renewed bool
	err := client.requestWorkerJSON(ctx, identity.accessToken, http.MethodPost, "/rest/v1/rpc/worker_renew_import_job", map[string]any{
		"p_job_id": lease.JobID, "p_lease_generation": lease.LeaseGeneration,
		"p_lease_seconds": leaseSeconds,
	}, &renewed)
	return renewed, err
}

// ReadWorkerPart opens exactly one already-authorized private object. The
// caller must close the response; the token and object path never leave the
// worker process.
func (client *Client) ReadWorkerPart(ctx context.Context, identity WorkerIdentity, objectPath string) (io.ReadCloser, error) {
	escapedPath := escapeStoragePath(objectPath)
	if escapedPath == "" {
		return nil, errors.New("source_part_invalid")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, client.baseURL+"/storage/v1/object/authenticated/"+importBucket+"/"+escapedPath, nil)
	if err != nil {
		return nil, fmt.Errorf("create storage request: %w", err)
	}
	req.Header.Set("apikey", client.publishableKey)
	req.Header.Set("Authorization", "Bearer "+identity.accessToken)
	res, err := client.workerClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("send storage request: %w", err)
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		res.Body.Close()
		return nil, &APIError{Status: res.StatusCode, Code: "storage_read_failed"}
	}
	return res.Body, nil
}

// PersistWorkerBatch accepts only canonical typed records and safe warning
// codes. The database derives owner/import provenance from the active lease.
func (client *Client) PersistWorkerBatch(ctx context.Context, identity WorkerIdentity, lease WorkerLease, fileID string, batchSequence int, records []map[string]any, warningCodes []string) error {
	return client.requestWorkerJSON(ctx, identity.accessToken, http.MethodPost, "/rest/v1/rpc/worker_persist_normalized_batch", map[string]any{
		"p_job_id": lease.JobID, "p_lease_generation": lease.LeaseGeneration, "p_import_file_id": fileID,
		"p_batch_sequence": batchSequence, "p_records": records, "p_warning_codes": warningCodes,
	}, nil)
}

func (client *Client) PersistLegacyXLSQuality(ctx context.Context, identity WorkerIdentity, lease WorkerLease, fileID string, quality normalization.LegacyXLSQuality) error {
	return client.requestWorkerJSON(ctx, identity.accessToken, http.MethodPost, "/rest/v1/rpc/worker_persist_legacy_xls_quality", map[string]any{
		"p_job_id": lease.JobID, "p_lease_generation": lease.LeaseGeneration, "p_import_file_id": fileID,
		"p_approved_sheet_count": quality.ApprovedSheetCount, "p_excluded_sheet_count": quality.ExcludedSheetCount,
		"p_unknown_sheet_count": quality.UnknownSheetCount, "p_covered_date_count": quality.CoveredDateCount,
		"p_candidate_metric_count": quality.CandidateMetricCount, "p_ambiguous_cell_count": quality.AmbiguousCellCount,
	}, nil)
}

func (client *Client) CompleteWorkerFile(ctx context.Context, identity WorkerIdentity, lease WorkerLease, fileID string, normalizedRecordCount int64, warningCodes []string) error {
	return client.requestWorkerJSON(ctx, identity.accessToken, http.MethodPost, "/rest/v1/rpc/worker_complete_import_file", map[string]any{
		"p_job_id": lease.JobID, "p_lease_generation": lease.LeaseGeneration,
		"p_import_file_id": fileID, "p_normalized_record_count": normalizedRecordCount,
		"p_warning_codes": warningCodes,
	}, nil)
}

func (client *Client) RetryWorkerImport(ctx context.Context, identity WorkerIdentity, lease WorkerLease, warningCode string) (string, error) {
	var state string
	err := client.requestWorkerJSON(ctx, identity.accessToken, http.MethodPost, "/rest/v1/rpc/worker_retry_import_job", map[string]any{
		"p_job_id": lease.JobID, "p_lease_generation": lease.LeaseGeneration,
		"p_warning_code": warningCode,
	}, &state)
	return state, err
}

func (client *Client) FinishWorkerImport(ctx context.Context, identity WorkerIdentity, lease WorkerLease, terminalState string, warningCodes []string) (bool, error) {
	var finished bool
	err := client.requestWorkerJSON(ctx, identity.accessToken, http.MethodPost, "/rest/v1/rpc/worker_finish_import_job", map[string]any{"p_job_id": lease.JobID, "p_lease_generation": lease.LeaseGeneration, "p_terminal_state": terminalState, "p_warning_codes": warningCodes}, &finished)
	return finished, err
}

func (client *Client) ListWorkerRawCleanup(ctx context.Context, identity WorkerIdentity, limit int) ([]WorkerCleanupCandidate, error) {
	var candidates []WorkerCleanupCandidate
	err := client.requestWorkerJSON(ctx, identity.accessToken, http.MethodPost, "/rest/v1/rpc/worker_raw_cleanup_source", map[string]int{"p_limit": limit}, &candidates)
	return candidates, err
}

func (client *Client) DeleteWorkerObjects(ctx context.Context, identity WorkerIdentity, objectPaths []string) error {
	if !identity.ImportWorker || identity.accessToken == "" {
		return errors.New("worker_configuration_invalid")
	}
	for start := 0; start < len(objectPaths); start += 1000 {
		end := start + 1000
		if end > len(objectPaths) {
			end = len(objectPaths)
		}
		if err := client.deleteObjects(ctx, identity.accessToken, objectPaths[start:end]); err != nil {
			return err
		}
	}
	return nil
}

func (client *Client) FinishWorkerRawCleanup(ctx context.Context, identity WorkerIdentity, importID string) (bool, error) {
	var finished bool
	err := client.requestWorkerJSON(ctx, identity.accessToken, http.MethodPost, "/rest/v1/rpc/worker_finish_raw_cleanup", map[string]string{"p_import_id": importID}, &finished)
	return finished, err
}

func (client *Client) rpc(ctx context.Context, accessToken, name string, body any) (imports.Snapshot, error) {
	var snapshot imports.Snapshot
	if err := client.requestJSON(ctx, accessToken, http.MethodPost, "/rest/v1/rpc/"+name, body, &snapshot); err != nil {
		return imports.Snapshot{}, err
	}
	if snapshot.ID == "" {
		return imports.Snapshot{}, &APIError{Status: http.StatusNotFound, Code: "not_found"}
	}
	return snapshot, nil
}

func (client *Client) deleteObjects(ctx context.Context, accessToken string, objectPaths []string) error {
	if len(objectPaths) == 0 {
		return nil
	}
	return client.requestJSON(
		ctx,
		accessToken,
		http.MethodDelete,
		"/storage/v1/object/"+importBucket,
		map[string]any{"prefixes": objectPaths},
		nil,
	)
}

func escapeStoragePath(objectPath string) string {
	segments := strings.Split(strings.Trim(objectPath, "/"), "/")
	if len(segments) == 0 {
		return ""
	}
	for index, segment := range segments {
		if segment == "" {
			return ""
		}
		segments[index] = url.PathEscape(segment)
	}
	return strings.Join(segments, "/")
}

func (client *Client) requestJSON(ctx context.Context, accessToken, method, path string, body, response any) error {
	return client.requestJSONWithHTTPClient(client.httpClient, ctx, accessToken, method, path, body, response)
}

func (client *Client) requestWorkerJSON(ctx context.Context, accessToken, method, path string, body, response any) error {
	return client.requestJSONWithHTTPClient(client.workerClient, ctx, accessToken, method, path, body, response)
}

func (client *Client) requestJSONWithHTTPClient(httpClient *http.Client, ctx context.Context, accessToken, method, path string, body, response any) error {
	encoded, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("encode supabase request: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, method, client.baseURL+path, bytes.NewReader(encoded))
	if err != nil {
		return fmt.Errorf("create supabase request: %w", err)
	}
	req.Header.Set("apikey", client.publishableKey)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/json")
	res, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("send supabase request: %w", err)
	}
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		var payload struct {
			Code string `json:"code"`
		}
		limited := io.LimitReader(res.Body, 64*1024)
		_ = json.NewDecoder(limited).Decode(&payload)
		if payload.Code == "" {
			payload.Code = "upstream_error"
		}
		return &APIError{Status: res.StatusCode, Code: payload.Code}
	}
	if response == nil || res.StatusCode == http.StatusNoContent {
		_, _ = io.Copy(io.Discard, res.Body)
		return nil
	}
	if err := json.NewDecoder(io.LimitReader(res.Body, 2*1024*1024)).Decode(response); err != nil {
		return fmt.Errorf("decode supabase response: %w", err)
	}
	return nil
}
