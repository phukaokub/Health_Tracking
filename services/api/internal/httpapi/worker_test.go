package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/phukaokub/Health_Tracking/services/api/internal/worker"
)

type fakeWorkerRunner struct {
	called bool
}

func (runner *fakeWorkerRunner) RunSyntheticBenchmark(_ context.Context, targetBytes int64) (worker.BenchmarkResult, error) {
	runner.called = true
	return worker.BenchmarkResult{ParserVersion: worker.ParserVersion, InputBytes: targetBytes, DeterministicRecovery: true}, nil
}
func (runner *fakeWorkerRunner) RunSyntheticMultiFileBenchmark(_ context.Context, targetBytes int64) (worker.BenchmarkResult, error) {
	runner.called = true
	return worker.BenchmarkResult{ParserVersion: worker.ParserVersion, FileCount: 5, InputBytes: targetBytes, DeterministicRecovery: true}, nil
}
func (runner *fakeWorkerRunner) ProcessOneImport(_ context.Context) (worker.Progress, error) {
	runner.called = true
	return worker.Progress{State: "completed", TotalFileCount: 1, ProcessedFileCount: 1}, nil
}
func (runner *fakeWorkerRunner) CleanupRawSources(_ context.Context) (worker.CleanupProgress, error) {
	runner.called = true
	return worker.CleanupProgress{State: "completed", ProcessedImportCount: 1, DeletedObjectCount: 1}, nil
}

func TestWorkerTriggerRequiresSecretAndRunsSyntheticMode(t *testing.T) {
	runner := &fakeWorkerRunner{}
	handler := NewWorkerTriggerHandler("synthetic-trigger-secret", runner, false)
	request := httptest.NewRequest(http.MethodPost, "/api/v1/worker/trigger", strings.NewReader(`{"target_bytes":1048576}`))
	request.Header.Set("X-Worker-Trigger", "synthetic-trigger-secret")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK || !runner.called {
		t.Fatalf("expected successful trigger, got %d %s", response.Code, response.Body.String())
	}
	var body workerTriggerResponse
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Mode != "synthetic_benchmark" || !body.WorkerAuthenticated {
		t.Fatalf("unexpected trigger response: %#v", body)
	}
}

func TestWorkerTriggerDoesNotInvokeRunnerWithWrongSecret(t *testing.T) {
	runner := &fakeWorkerRunner{}
	handler := NewWorkerTriggerHandler("synthetic-trigger-secret", runner, false)
	request := httptest.NewRequest(http.MethodPost, "/api/v1/worker/trigger", nil)
	request.Header.Set("X-Worker-Trigger", "wrong")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized || runner.called {
		t.Fatalf("wrong secret was not rejected safely: %d %v", response.Code, runner.called)
	}
}

func TestWorkerTriggerRejectsRealImportMode(t *testing.T) {
	runner := &fakeWorkerRunner{}
	handler := NewWorkerTriggerHandler("synthetic-trigger-secret", runner, false)
	request := httptest.NewRequest(http.MethodPost, "/api/v1/worker/trigger", strings.NewReader(`{"mode":"process_import"}`))
	request.Header.Set("X-Worker-Trigger", "synthetic-trigger-secret")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusBadRequest || runner.called {
		t.Fatalf("real import mode was not rejected: %d %v", response.Code, runner.called)
	}
}

func TestWorkerTriggerAllowsLeaseBoundImportModeOnlyWhenEnabled(t *testing.T) {
	runner := &fakeWorkerRunner{}
	handler := NewWorkerTriggerHandler("synthetic-trigger-secret", runner, true)
	request := httptest.NewRequest(http.MethodPost, "/api/v1/worker/trigger", strings.NewReader(`{"mode":"process_import"}`))
	request.Header.Set("X-Worker-Trigger", "synthetic-trigger-secret")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK || !runner.called {
		t.Fatalf("enabled import mode failed: %d %s", response.Code, response.Body.String())
	}
}

func TestWorkerTriggerRunsMultiFileBenchmark(t *testing.T) {
	runner := &fakeWorkerRunner{}
	handler := NewWorkerTriggerHandler("synthetic-trigger-secret", runner, false)
	request := httptest.NewRequest(http.MethodPost, "/api/v1/worker/trigger", strings.NewReader(`{"mode":"synthetic_multifile_benchmark","target_bytes":346030080}`))
	request.Header.Set("X-Worker-Trigger", "synthetic-trigger-secret")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK || !runner.called {
		t.Fatalf("multi-file benchmark failed: %d %s", response.Code, response.Body.String())
	}
}

func TestWorkerTriggerAllowsCleanupOnlyWhenEnabled(t *testing.T) {
	for _, enabled := range []bool{false, true} {
		runner := &fakeWorkerRunner{}
		handler := NewWorkerTriggerHandler("synthetic-trigger-secret", runner, enabled)
		request := httptest.NewRequest(http.MethodPost, "/api/v1/worker/trigger", strings.NewReader(`{"mode":"cleanup_sources"}`))
		request.Header.Set("X-Worker-Trigger", "synthetic-trigger-secret")
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		expected := http.StatusBadRequest
		if enabled {
			expected = http.StatusOK
		}
		if response.Code != expected || runner.called != enabled {
			t.Fatalf("cleanup gate mismatch enabled=%v status=%d called=%v", enabled, response.Code, runner.called)
		}
	}
}
