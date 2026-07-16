package supabase

import (
	"context"
	"encoding/json"
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
