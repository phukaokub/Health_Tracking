package main

import (
	"context"
	"errors"

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
