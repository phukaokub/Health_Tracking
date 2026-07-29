package worker

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
)

func TestSyntheticBenchmarkIsDeterministicAndBounded(t *testing.T) {
	result, err := RunSyntheticBenchmark(context.Background(), MinSyntheticBenchmarkBytes)
	if err != nil {
		t.Fatal(err)
	}
	if !result.DeterministicRecovery || result.ResumedFromBatch != 1 || result.NormalizedRecordCount == 0 {
		t.Fatalf("unexpected recovery result: %+v", result)
	}
	if result.FileCount != 1 || result.InputBytes != MinSyntheticBenchmarkBytes {
		t.Fatalf("single-file benchmark size drifted: %+v", result)
	}
	if result.InputBytes < MinSyntheticBenchmarkBytes || result.InputBytes > DefaultSyntheticBenchmarkBytes {
		t.Fatalf("unexpected input size: %+v", result)
	}
}

func TestSyntheticBenchmarkAtStagingTarget(t *testing.T) {
	result, err := RunSyntheticBenchmark(context.Background(), DefaultSyntheticBenchmarkBytes)
	if err != nil {
		t.Fatal(err)
	}
	if !result.DeterministicRecovery || result.InputBytes != DefaultSyntheticBenchmarkBytes {
		t.Fatalf("staging target did not produce deterministic recovery: %+v", result)
	}
}

func TestSyntheticMultiFileBenchmarkAtExportTarget(t *testing.T) {
	result, err := RunSyntheticMultiFileBenchmark(context.Background(), DefaultSyntheticMultiFileBenchmarkBytes)
	if err != nil {
		t.Fatal(err)
	}
	if !result.DeterministicRecovery || result.FileCount != 5 || result.InputBytes != DefaultSyntheticMultiFileBenchmarkBytes {
		t.Fatalf("multi-file target did not produce deterministic recovery: %+v", result)
	}
}

func TestBenchmarkResultIsPrivacySafe(t *testing.T) {
	result := BenchmarkResult{ParserVersion: ParserVersion, InputBytes: 1, DeterministicRecovery: true}
	encoded := strings.ToLower(string(mustJSON(result)))
	for _, forbidden := range []string{"payload", "email", "password", "token", "path", "latitude", "longitude", "record_id"} {
		if strings.Contains(encoded, forbidden) {
			t.Fatalf("unsafe benchmark field %q: %s", forbidden, encoded)
		}
	}
}

func mustJSON(value any) []byte {
	encoded, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return encoded
}
