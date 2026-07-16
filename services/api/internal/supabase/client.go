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
)

const importBucket = "health-imports"

type Client struct {
	baseURL        string
	publishableKey string
	httpClient     *http.Client
}

type APIError struct {
	Status int
	Code   string
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
	return &Client{baseURL: baseURL, publishableKey: publishableKey, httpClient: httpClient}, nil
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

func (client *Client) requestJSON(ctx context.Context, accessToken, method, path string, body, response any) error {
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
	res, err := client.httpClient.Do(req)
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
