package main

import (
	"context"
	"errors"
	"io"

	"github.com/phukaokub/Health_Tracking/services/api/internal/supabase"
	"github.com/phukaokub/Health_Tracking/services/api/internal/worker"
)

type workerTriggerService struct {
	client   workerRuntimeClient
	email    string
	password string
}

type workerRuntimeClient interface {
	AuthenticateWorker(context.Context, string, string) (supabase.WorkerIdentity, error)
	ClaimWorkerImport(context.Context, supabase.WorkerIdentity, string, int) (*supabase.WorkerLease, error)
	WorkerImportSource(context.Context, supabase.WorkerIdentity, supabase.WorkerLease) ([]supabase.WorkerSourceFile, error)
	RenewWorkerImport(context.Context, supabase.WorkerIdentity, supabase.WorkerLease, int) (bool, error)
	ReadWorkerPart(context.Context, supabase.WorkerIdentity, string) (io.ReadCloser, error)
	PersistWorkerBatch(context.Context, supabase.WorkerIdentity, supabase.WorkerLease, string, int, []map[string]any, []string) error
	CompleteWorkerFile(context.Context, supabase.WorkerIdentity, supabase.WorkerLease, string, int64, []string) error
	RetryWorkerImport(context.Context, supabase.WorkerIdentity, supabase.WorkerLease, string) (string, error)
	FinishWorkerImport(context.Context, supabase.WorkerIdentity, supabase.WorkerLease, string, []string) (bool, error)
	ListWorkerRawCleanup(context.Context, supabase.WorkerIdentity, int) ([]supabase.WorkerCleanupCandidate, error)
	DeleteWorkerObjects(context.Context, supabase.WorkerIdentity, []string) error
	FinishWorkerRawCleanup(context.Context, supabase.WorkerIdentity, string) (bool, error)
}

func (service workerTriggerService) RunSyntheticBenchmark(ctx context.Context, targetBytes int64) (worker.BenchmarkResult, error) {
	if service.client == nil || service.email == "" || service.password == "" {
		return worker.BenchmarkResult{}, errors.New("worker_configuration_invalid")
	}
	identity, err := service.client.AuthenticateWorker(ctx, service.email, service.password)
	if err != nil {
		return worker.BenchmarkResult{}, err
	}
	if !identity.ImportWorker {
		return worker.BenchmarkResult{}, errors.New("worker_configuration_invalid")
	}
	return worker.RunSyntheticBenchmark(ctx, targetBytes)
}

func (service workerTriggerService) RunSyntheticMultiFileBenchmark(ctx context.Context, targetBytes int64) (worker.BenchmarkResult, error) {
	if service.client == nil || service.email == "" || service.password == "" {
		return worker.BenchmarkResult{}, errors.New("worker_configuration_invalid")
	}
	identity, err := service.client.AuthenticateWorker(ctx, service.email, service.password)
	if err != nil {
		return worker.BenchmarkResult{}, err
	}
	if !identity.ImportWorker {
		return worker.BenchmarkResult{}, errors.New("worker_configuration_invalid")
	}
	return worker.RunSyntheticMultiFileBenchmark(ctx, targetBytes)
}

// ProcessOneImport performs one server-selected lease. It receives no owner,
// import ID, object path, or raw source from the HTTP request.
func (service workerTriggerService) ProcessOneImport(ctx context.Context) (worker.Progress, error) {
	if service.client == nil || service.email == "" || service.password == "" {
		return worker.Progress{}, errors.New("worker_configuration_invalid")
	}
	identity, err := service.client.AuthenticateWorker(ctx, service.email, service.password)
	if err != nil || !identity.ImportWorker {
		return worker.Progress{}, errors.New("worker_configuration_invalid")
	}
	lease, err := service.client.ClaimWorkerImport(ctx, identity, worker.ParserVersion, int(worker.LeaseDuration.Seconds()))
	if err != nil || lease == nil {
		return worker.Progress{State: "idle"}, err
	}
	files, err := service.client.WorkerImportSource(ctx, identity, *lease)
	if err != nil {
		return service.fail(ctx, identity, *lease, "source_part_unavailable", true)
	}
	progress := worker.Progress{TotalFileCount: len(files), State: "processing"}
	opener := privatePartOpener{client: service.client, identity: identity}
	batchSequence := 0
	for _, file := range files {
		if err := service.renew(ctx, identity, *lease); err != nil {
			return worker.Progress{}, err
		}
		parts := make([]worker.SourcePart, 0, len(file.Parts))
		for _, part := range file.Parts {
			parts = append(parts, worker.SourcePart{Index: part.PartIndex, Bytes: part.ByteLength, SHA256: part.ContentSHA256, Path: part.ObjectPath})
		}
		result, parseErr := worker.ParsePrivateParts(ctx, opener, parts)
		if parseErr != nil {
			code := "source_part_invalid"
			retryable := false
			if parseErr.Error() == "source_part_unavailable" {
				code = "source_part_unavailable"
				retryable = true
			}
			return service.fail(ctx, identity, *lease, code, retryable)
		}
		warnings := make([]string, 0, len(result.Warnings))
		seenWarnings := make(map[string]struct{}, len(result.Warnings))
		for _, warning := range result.Warnings {
			if _, exists := seenWarnings[warning.Code]; exists {
				continue
			}
			seenWarnings[warning.Code] = struct{}{}
			warnings = append(warnings, warning.Code)
		}
		if len(warnings) > worker.MaxWarningCodes {
			return service.fail(ctx, identity, *lease, "warning_limit_exceeded", false)
		}
		fileRecordCount := int64(0)
		for _, batch := range worker.CanonicalBatches(result) {
			if err := service.renew(ctx, identity, *lease); err != nil {
				return worker.Progress{}, err
			}
			if err := service.client.PersistWorkerBatch(ctx, identity, *lease, file.ID, batchSequence, batch, warnings); err != nil {
				return service.fail(ctx, identity, *lease, "canonical_persistence_failed", true)
			}
			batchSequence++
			fileRecordCount += int64(len(batch))
			progress.NormalizedRecordCount += int64(len(batch))
		}
		if err := service.client.CompleteWorkerFile(ctx, identity, *lease, file.ID, fileRecordCount, warnings); err != nil {
			return service.fail(ctx, identity, *lease, "file_checkpoint_failed", true)
		}
		progress.ProcessedFileCount++
		progress.WarningCodes = mergeWarningCodes(progress.WarningCodes, warnings)
		if len(progress.WarningCodes) > worker.MaxWarningCodes {
			return service.fail(ctx, identity, *lease, "warning_limit_exceeded", false)
		}
	}
	if len(progress.WarningCodes) > 0 {
		progress.State = "completed_with_warnings"
	} else {
		progress.State = "completed"
	}
	if _, err := service.client.FinishWorkerImport(ctx, identity, *lease, progress.State, progress.WarningCodes); err != nil {
		return worker.Progress{}, err
	}
	return progress, progress.Validate()
}

func (service workerTriggerService) CleanupRawSources(ctx context.Context) (worker.CleanupProgress, error) {
	if service.client == nil || service.email == "" || service.password == "" {
		return worker.CleanupProgress{}, errors.New("worker_configuration_invalid")
	}
	identity, err := service.client.AuthenticateWorker(ctx, service.email, service.password)
	if err != nil || !identity.ImportWorker {
		return worker.CleanupProgress{}, errors.New("worker_configuration_invalid")
	}
	candidates, err := service.client.ListWorkerRawCleanup(ctx, identity, 25)
	if err != nil {
		return worker.CleanupProgress{}, err
	}
	progress := worker.CleanupProgress{State: "idle"}
	for _, candidate := range candidates {
		if err := service.client.DeleteWorkerObjects(ctx, identity, candidate.ObjectPaths); err != nil {
			return progress, err
		}
		finished, err := service.client.FinishWorkerRawCleanup(ctx, identity, candidate.ImportID)
		if err != nil || !finished {
			return progress, errors.New("raw_cleanup_incomplete")
		}
		progress.ProcessedImportCount++
		progress.DeletedObjectCount += len(candidate.ObjectPaths)
	}
	if progress.ProcessedImportCount > 0 {
		progress.State = "completed"
	}
	return progress, progress.Validate()
}

func (service workerTriggerService) renew(ctx context.Context, identity supabase.WorkerIdentity, lease supabase.WorkerLease) error {
	renewed, err := service.client.RenewWorkerImport(ctx, identity, lease, int(worker.LeaseDuration.Seconds()))
	if err != nil {
		return err
	}
	if !renewed {
		return errors.New("lease_lost")
	}
	return nil
}

func (service workerTriggerService) fail(ctx context.Context, identity supabase.WorkerIdentity, lease supabase.WorkerLease, warning string, retryable bool) (worker.Progress, error) {
	if retryable {
		state, err := service.client.RetryWorkerImport(ctx, identity, lease, warning)
		if err == nil {
			return worker.Progress{State: state, WarningCodes: []string{warning}}, errors.New(warning)
		}
		return worker.Progress{}, err
	}
	_, _ = service.client.FinishWorkerImport(ctx, identity, lease, "failed", []string{warning})
	return worker.Progress{State: "failed", WarningCodes: []string{warning}}, errors.New(warning)
}

func mergeWarningCodes(current, additions []string) []string {
	seen := make(map[string]struct{}, len(current)+len(additions))
	merged := make([]string, 0, len(current)+len(additions))
	for _, group := range [][]string{current, additions} {
		for _, code := range group {
			if _, exists := seen[code]; exists {
				continue
			}
			seen[code] = struct{}{}
			merged = append(merged, code)
		}
	}
	return merged
}

type privatePartOpener struct {
	client   workerRuntimeClient
	identity supabase.WorkerIdentity
}

func (opener privatePartOpener) OpenPart(ctx context.Context, path string) (io.ReadCloser, error) {
	return opener.client.ReadWorkerPart(ctx, opener.identity, path)
}
