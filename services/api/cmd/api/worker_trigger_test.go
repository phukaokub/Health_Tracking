package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"reflect"
	"testing"

	"github.com/phukaokub/Health_Tracking/services/api/internal/supabase"
)

type fakeWorkerRuntime struct {
	lease              supabase.WorkerLease
	files              []supabase.WorkerSourceFile
	parts              map[string][]byte
	batchSequences     []int
	completedFileIDs   []string
	finishedState      string
	renewCount         int
	cleanupCandidates  []supabase.WorkerCleanupCandidate
	deletedObjectCount int
	finishedCleanup    int
}

func (runtime *fakeWorkerRuntime) AuthenticateWorker(context.Context, string, string) (supabase.WorkerIdentity, error) {
	return supabase.WorkerIdentity{ImportWorker: true, Subject: "synthetic-worker"}, nil
}
func (runtime *fakeWorkerRuntime) ClaimWorkerImport(context.Context, supabase.WorkerIdentity, string, int) (*supabase.WorkerLease, error) {
	return &runtime.lease, nil
}
func (runtime *fakeWorkerRuntime) WorkerImportSource(context.Context, supabase.WorkerIdentity, supabase.WorkerLease) ([]supabase.WorkerSourceFile, error) {
	return runtime.files, nil
}
func (runtime *fakeWorkerRuntime) RenewWorkerImport(context.Context, supabase.WorkerIdentity, supabase.WorkerLease, int) (bool, error) {
	runtime.renewCount++
	return true, nil
}
func (runtime *fakeWorkerRuntime) ReadWorkerPart(_ context.Context, _ supabase.WorkerIdentity, path string) (io.ReadCloser, error) {
	return io.NopCloser(bytes.NewReader(runtime.parts[path])), nil
}
func (runtime *fakeWorkerRuntime) PersistWorkerBatch(_ context.Context, _ supabase.WorkerIdentity, _ supabase.WorkerLease, _ string, sequence int, _ []map[string]any, _ []string) error {
	runtime.batchSequences = append(runtime.batchSequences, sequence)
	return nil
}
func (runtime *fakeWorkerRuntime) CompleteWorkerFile(_ context.Context, _ supabase.WorkerIdentity, _ supabase.WorkerLease, fileID string, _ int64, _ []string) error {
	runtime.completedFileIDs = append(runtime.completedFileIDs, fileID)
	return nil
}
func (runtime *fakeWorkerRuntime) RetryWorkerImport(context.Context, supabase.WorkerIdentity, supabase.WorkerLease, string) (string, error) {
	return "queued", nil
}
func (runtime *fakeWorkerRuntime) FinishWorkerImport(_ context.Context, _ supabase.WorkerIdentity, _ supabase.WorkerLease, state string, _ []string) (bool, error) {
	runtime.finishedState = state
	return true, nil
}
func (runtime *fakeWorkerRuntime) ListWorkerRawCleanup(context.Context, supabase.WorkerIdentity, int) ([]supabase.WorkerCleanupCandidate, error) {
	return runtime.cleanupCandidates, nil
}
func (runtime *fakeWorkerRuntime) DeleteWorkerObjects(_ context.Context, _ supabase.WorkerIdentity, paths []string) error {
	runtime.deletedObjectCount += len(paths)
	return nil
}
func (runtime *fakeWorkerRuntime) FinishWorkerRawCleanup(context.Context, supabase.WorkerIdentity, string) (bool, error) {
	runtime.finishedCleanup++
	return true, nil
}

func TestProcessOneImportUsesGlobalBatchSequenceAndCompletesEveryFile(t *testing.T) {
	first := []byte(`{"records":[{"type":"heart_rate","record_id":"synthetic-first","started_at":"2026-01-02T03:04:05Z","unit":"bpm","value":72}]}`)
	second := []byte(`{"records":[{"type":"steps","record_id":"synthetic-second","started_at":"2026-01-02T03:04:05Z","unit":"count","value":10}]}`)
	runtime := &fakeWorkerRuntime{
		lease: supabase.WorkerLease{JobID: "job", ImportID: "import", LeaseGeneration: "generation"},
		parts: map[string][]byte{"part-first": first, "part-second": second},
	}
	runtime.files = []supabase.WorkerSourceFile{
		sourceFile("file-first", "part-first", first),
		sourceFile("file-second", "part-second", second),
	}
	service := workerTriggerService{client: runtime, email: "synthetic", password: "synthetic"}

	progress, err := service.ProcessOneImport(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(runtime.batchSequences, []int{0, 1}) {
		t.Fatalf("batch sequences were not global: %#v", runtime.batchSequences)
	}
	if !reflect.DeepEqual(runtime.completedFileIDs, []string{"file-first", "file-second"}) {
		t.Fatalf("files were not completed exactly once: %#v", runtime.completedFileIDs)
	}
	if progress.ProcessedFileCount != 2 || progress.NormalizedRecordCount != 2 || runtime.finishedState != "completed" {
		t.Fatalf("unexpected processing result: %#v state=%s", progress, runtime.finishedState)
	}
	if runtime.renewCount < 4 {
		t.Fatalf("lease was not renewed around file and batch boundaries: %d", runtime.renewCount)
	}
}

func TestCleanupRawSourcesReturnsCountsWithoutIdentifiers(t *testing.T) {
	runtime := &fakeWorkerRuntime{cleanupCandidates: []supabase.WorkerCleanupCandidate{
		{ImportID: "synthetic-import", ObjectPaths: []string{"one", "two"}},
	}}
	service := workerTriggerService{client: runtime, email: "synthetic", password: "synthetic"}
	progress, err := service.CleanupRawSources(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if progress.State != "completed" || progress.ProcessedImportCount != 1 || progress.DeletedObjectCount != 2 {
		t.Fatalf("unexpected cleanup progress: %#v", progress)
	}
	if runtime.finishedCleanup != 1 || runtime.deletedObjectCount != 2 {
		t.Fatalf("cleanup adapter did not converge: %#v", runtime)
	}
}

func TestMergeWarningCodesIsDeterministicAndUnique(t *testing.T) {
	got := mergeWarningCodes(
		[]string{"route_content_dropped", "sensitive_record_excluded"},
		[]string{"sensitive_record_excluded", "metric_mapping_unknown"},
	)
	want := []string{"route_content_dropped", "sensitive_record_excluded", "metric_mapping_unknown"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("warning codes were not merged deterministically: got %#v want %#v", got, want)
	}
}

func sourceFile(fileID, path string, data []byte) supabase.WorkerSourceFile {
	digest := sha256.Sum256(data)
	return supabase.WorkerSourceFile{
		ID: fileID, LogicalBytes: int64(len(data)), ContentSHA256: hex.EncodeToString(digest[:]),
		Parts: []supabase.WorkerSourcePart{{
			PartIndex: 0, ByteLength: int64(len(data)),
			ContentSHA256: hex.EncodeToString(digest[:]), ObjectPath: path,
		}},
	}
}
