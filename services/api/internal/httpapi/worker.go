package httpapi

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/phukaokub/Health_Tracking/services/api/internal/worker"
)

type WorkerBenchmarkRunner interface {
	RunSyntheticBenchmark(context.Context, int64) (worker.BenchmarkResult, error)
}

type workerTriggerRequest struct {
	Mode        string `json:"mode"`
	TargetBytes int64  `json:"target_bytes"`
}

type workerTriggerResponse struct {
	Status              string                 `json:"status"`
	Mode                string                 `json:"mode"`
	WorkerAuthenticated bool                   `json:"worker_authenticated"`
	Benchmark           worker.BenchmarkResult `json:"benchmark"`
}

func NewWorkerTriggerHandler(triggerSecret string, runner WorkerBenchmarkRunner) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method_not_allowed"})
			return
		}
		if !secretMatches(triggerSecret, r.Header.Get("X-Worker-Trigger")) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "worker_trigger_unauthorized"})
			return
		}
		if runner == nil || strings.TrimSpace(triggerSecret) == "" {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "worker_configuration_invalid"})
			return
		}
		request := workerTriggerRequest{Mode: "synthetic_benchmark", TargetBytes: worker.DefaultSyntheticBenchmarkBytes}
		decoder := json.NewDecoder(io.LimitReader(r.Body, 16*1024))
		decoder.DisallowUnknownFields()
		if err := decoder.Decode(&request); err != nil && err != io.EOF {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "worker_trigger_request_invalid"})
			return
		}
		if request.Mode == "" {
			request.Mode = "synthetic_benchmark"
		}
		if request.Mode != "synthetic_benchmark" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "worker_mode_unsupported"})
			return
		}
		if request.TargetBytes == 0 {
			request.TargetBytes = worker.DefaultSyntheticBenchmarkBytes
		}
		ctx, cancel := context.WithTimeout(r.Context(), 240*time.Second)
		defer cancel()
		result, err := runner.RunSyntheticBenchmark(ctx, request.TargetBytes)
		if err != nil {
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": "worker_benchmark_failed"})
			return
		}
		writeJSON(w, http.StatusOK, workerTriggerResponse{
			Status:              "ok",
			Mode:                request.Mode,
			WorkerAuthenticated: true,
			Benchmark:           result,
		})
	})
}

func secretMatches(expected, supplied string) bool {
	if strings.TrimSpace(expected) == "" || supplied == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(expected), []byte(supplied)) == 1
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
