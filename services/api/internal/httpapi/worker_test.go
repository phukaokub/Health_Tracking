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

func TestWorkerTriggerRequiresSecretAndRunsSyntheticMode(t *testing.T) {
	runner := &fakeWorkerRunner{}
	handler := NewWorkerTriggerHandler("synthetic-trigger-secret", runner)
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
	handler := NewWorkerTriggerHandler("synthetic-trigger-secret", runner)
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
	handler := NewWorkerTriggerHandler("synthetic-trigger-secret", runner)
	request := httptest.NewRequest(http.MethodPost, "/api/v1/worker/trigger", strings.NewReader(`{"mode":"process_import"}`))
	request.Header.Set("X-Worker-Trigger", "synthetic-trigger-secret")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusBadRequest || runner.called {
		t.Fatalf("real import mode was not rejected: %d %v", response.Code, runner.called)
	}
}
