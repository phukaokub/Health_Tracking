package supabase

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"
)

func TestNewClientRequiresPublishableKey(t *testing.T) {
	if _, err := NewClient("http://127.0.0.1:54321", "", nil); err == nil {
		t.Fatal("missing publishable key was accepted")
	}
}

func TestDeleteImportUsesUserScopedStorageAPIThenFinishesMetadata(t *testing.T) {
	var calls []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer user-token" || r.Header.Get("apikey") != "publishable-key" {
			t.Fatal("request did not forward publishable key and user token")
		}
		calls = append(calls, r.Method+" "+r.URL.Path)
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/rest/v1/rpc/begin_import_delete":
			_, _ = w.Write([]byte(`{"id":"10000000-0000-4000-8000-000000000001","state":"deleting","object_paths":["imports/u/i/f/part-0"]}`))
		case "/storage/v1/object/health-imports":
			var body struct {
				Prefixes []string `json:"prefixes"`
			}
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil || !reflect.DeepEqual(body.Prefixes, []string{"imports/u/i/f/part-0"}) {
				t.Fatalf("unexpected Storage delete body: %#v, %v", body, err)
			}
			_, _ = w.Write([]byte(`[]`))
		case "/rest/v1/rpc/finish_import_delete":
			_, _ = w.Write([]byte(`{"id":"10000000-0000-4000-8000-000000000001","state":"deleted","files":[]}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	client, err := NewClient(server.URL, "publishable-key", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	snapshot, err := client.DeleteImport(context.Background(), "user-token", "10000000-0000-4000-8000-000000000001")
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.State != "deleted" {
		t.Fatalf("expected deleted snapshot, got %#v", snapshot)
	}
	want := []string{
		"POST /rest/v1/rpc/begin_import_delete",
		"DELETE /storage/v1/object/health-imports",
		"POST /rest/v1/rpc/finish_import_delete",
	}
	if !reflect.DeepEqual(calls, want) {
		t.Fatalf("unexpected call order: %#v", calls)
	}
}

func TestCleanupImportsListsOnlyCallerExpiredRunsThenDeletesStorageFirst(t *testing.T) {
	var calls []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls = append(calls, r.Method+" "+r.URL.Path)
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/rest/v1/rpc/list_expired_imports":
			_, _ = w.Write([]byte(`[{"import_id":"10000000-0000-4000-8000-000000000001"}]`))
		case "/rest/v1/rpc/begin_import_delete":
			_, _ = w.Write([]byte(`{"state":"deleting","object_paths":[]}`))
		case "/rest/v1/rpc/finish_import_delete":
			_, _ = w.Write([]byte(`{"id":"10000000-0000-4000-8000-000000000001","state":"deleted","files":[]}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()
	client, err := NewClient(server.URL, "publishable-key", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	result, err := client.CleanupImports(context.Background(), "user-token")
	if err != nil || result.DeletedCount != 1 {
		t.Fatalf("expected one cleanup, got %#v, %v", result, err)
	}
	want := []string{
		"POST /rest/v1/rpc/list_expired_imports",
		"POST /rest/v1/rpc/begin_import_delete",
		"POST /rest/v1/rpc/finish_import_delete",
	}
	if !reflect.DeepEqual(calls, want) {
		t.Fatalf("unexpected cleanup calls: %#v", calls)
	}
}

func TestAuthenticateWorkerUsesPublishableKeyAndRequiresAppMetadataClaim(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/auth/v1/token" || r.URL.Query().Get("grant_type") != "password" {
			t.Fatalf("unexpected auth path: %s", r.URL.String())
		}
		if r.Header.Get("apikey") != "publishable-key" || r.Header.Get("Authorization") != "Bearer publishable-key" {
			t.Fatal("worker auth did not use the publishable key")
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"access_token":"redacted","user":{"id":"00000000-0000-4000-8000-000000000099","app_metadata":{"import_worker":true}}}`))
	}))
	defer server.Close()
	client, err := NewClient(server.URL, "publishable-key", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	identity, err := client.AuthenticateWorker(context.Background(), "worker@staging.invalid", "synthetic-password")
	if err != nil || !identity.ImportWorker {
		t.Fatalf("worker identity was not accepted: %#v, %v", identity, err)
	}
}

func TestWorkerStorageReadUsesShortLivedWorkerToken(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/storage/v1/object/authenticated/health-imports/imports/synthetic" || r.Header.Get("Authorization") != "Bearer worker-token" {
			t.Fatalf("unexpected private read: %s", r.URL.String())
		}
		_, _ = w.Write([]byte("{}"))
	}))
	defer server.Close()
	client, err := NewClient(server.URL, "publishable-key", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	body, err := client.ReadWorkerPart(context.Background(), WorkerIdentity{ImportWorker: true, Subject: "synthetic", accessToken: "worker-token"}, "imports/synthetic")
	if err != nil {
		t.Fatal(err)
	}
	defer body.Close()
	if bytes, _ := io.ReadAll(body); string(bytes) != "{}" {
		t.Fatal("unexpected private body")
	}
}

func TestDeleteWorkerObjectsUsesBoundedStorageBatches(t *testing.T) {
	var batchSizes []int
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodDelete || r.URL.Path != "/storage/v1/object/health-imports" {
			t.Fatalf("unexpected cleanup request: %s %s", r.Method, r.URL.Path)
		}
		if r.Header.Get("Authorization") != "Bearer worker-token" {
			t.Fatal("cleanup request did not use the short-lived worker token")
		}
		var body struct {
			Prefixes []string `json:"prefixes"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		batchSizes = append(batchSizes, len(body.Prefixes))
		_, _ = w.Write([]byte(`[]`))
	}))
	defer server.Close()

	client, err := NewClient(server.URL, "publishable-key", server.Client())
	if err != nil {
		t.Fatal(err)
	}
	paths := make([]string, 1001)
	for index := range paths {
		paths[index] = fmt.Sprintf("imports/synthetic/part-%d", index)
	}
	err = client.DeleteWorkerObjects(
		context.Background(),
		WorkerIdentity{ImportWorker: true, Subject: "synthetic", accessToken: "worker-token"},
		paths,
	)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(batchSizes, []int{1000, 1}) {
		t.Fatalf("cleanup requests were not bounded: %#v", batchSizes)
	}
}
