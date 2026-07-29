package main

import (
	"context"
	"errors"
	"io"

	"github.com/phukaokub/Health_Tracking/services/api/internal/supabase"
	"github.com/phukaokub/Health_Tracking/services/api/internal/worker"
)

type workerTriggerService struct {
	client   *supabase.Client
	email    string
	password string
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
		return service.fail(ctx, identity, *lease, "source_part_unavailable")
	}
	progress := worker.Progress{TotalFileCount: len(files), State: "processing"}
	opener := privatePartOpener{client: service.client, identity: identity}
	for _, file := range files {
		parts := make([]worker.SourcePart, 0, len(file.Parts))
		for _, part := range file.Parts {
			parts = append(parts, worker.SourcePart{Index: part.PartIndex, Bytes: part.ByteLength, SHA256: part.ContentSHA256, Path: part.ObjectPath})
		}
		result, parseErr := worker.ParsePrivateParts(ctx, opener, parts)
		if parseErr != nil {
			return service.fail(ctx, identity, *lease, "source_part_invalid")
		}
		warnings := make([]string, 0, len(result.Warnings))
		for _, warning := range result.Warnings {
			warnings = append(warnings, warning.Code)
		}
		for sequence, batch := range worker.CanonicalBatches(result) {
			if err := service.client.PersistWorkerBatch(ctx, identity, *lease, file.ID, sequence, batch, warnings); err != nil {
				return service.fail(ctx, identity, *lease, "canonical_persistence_failed")
			}
			progress.NormalizedRecordCount += int64(len(batch))
		}
		progress.ProcessedFileCount++
		progress.WarningCodes = append(progress.WarningCodes, warnings...)
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

func (service workerTriggerService) fail(ctx context.Context, identity supabase.WorkerIdentity, lease supabase.WorkerLease, warning string) (worker.Progress, error) {
	_, _ = service.client.FinishWorkerImport(ctx, identity, lease, "failed", []string{warning})
	return worker.Progress{State: "failed", WarningCodes: []string{warning}}, errors.New(warning)
}

type privatePartOpener struct {
	client   *supabase.Client
	identity supabase.WorkerIdentity
}

func (opener privatePartOpener) OpenPart(ctx context.Context, path string) (io.ReadCloser, error) {
	return opener.client.ReadWorkerPart(ctx, opener.identity, path)
}
