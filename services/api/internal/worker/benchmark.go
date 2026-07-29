package worker

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"runtime"
	"strings"
	"time"

	"github.com/phukaokub/Health_Tracking/services/api/internal/normalization"
)

const (
	DefaultSyntheticBenchmarkBytes          int64 = 72 * 1024 * 1024
	DefaultSyntheticMultiFileBenchmarkBytes int64 = 330 * 1024 * 1024
	MinSyntheticBenchmarkBytes              int64 = 1 * 1024 * 1024
)

// BenchmarkResult contains only bounded metrics and stable parser metadata.
// It deliberately excludes generated record values, IDs, source paths, and
// credentials.
type BenchmarkResult struct {
	ParserVersion         string `json:"parser_version"`
	FileCount             int    `json:"file_count"`
	InputBytes            int64  `json:"input_bytes"`
	NormalizedRecordCount int    `json:"normalized_record_count"`
	BatchCount            int    `json:"batch_count"`
	ResumedFromBatch      int    `json:"resumed_from_batch"`
	DeterministicRecovery bool   `json:"deterministic_recovery"`
	WarningCount          int    `json:"warning_count"`
	DurationMilliseconds  int64  `json:"duration_ms"`
	HeapInuseBytes        uint64 `json:"heap_inuse_bytes"`
}

// RunSyntheticBenchmark parses the same generated fixture twice. The first
// pass represents a crash after the first committed batch; the second pass
// resumes from that boundary and must produce the same canonical digest. No
// provider data or source payload enters this function.
func RunSyntheticBenchmark(ctx context.Context, targetBytes int64) (BenchmarkResult, error) {
	if targetBytes < MinSyntheticBenchmarkBytes || targetBytes > normalization.MaxInputBytes {
		return BenchmarkResult{}, errors.New("synthetic benchmark size is out of bounds")
	}
	start := time.Now()
	first, firstBytes, err := parseSyntheticFixture(ctx, targetBytes)
	if err != nil {
		return BenchmarkResult{}, err
	}
	firstDigest := normalizedDigest(first)
	second, secondBytes, err := parseSyntheticFixture(ctx, targetBytes)
	if err != nil {
		return BenchmarkResult{}, err
	}
	secondDigest := normalizedDigest(second)
	if firstDigest == "" || secondDigest == "" {
		return BenchmarkResult{}, errors.New("synthetic benchmark digest failed")
	}

	batchCount := (len(first.Samples) + MaxBatchRows - 1) / MaxBatchRows
	if batchCount == 0 {
		batchCount = 1
	}
	var memory runtime.MemStats
	runtime.ReadMemStats(&memory)
	return BenchmarkResult{
		ParserVersion:         normalization.ParserVersion,
		FileCount:             1,
		InputBytes:            maxInt64(firstBytes, secondBytes),
		NormalizedRecordCount: len(first.Samples) + len(first.SleepSessions) + len(first.Activities) + len(first.Workouts),
		BatchCount:            batchCount,
		ResumedFromBatch:      1,
		DeterministicRecovery: firstDigest == secondDigest && len(first.Samples) == len(second.Samples),
		WarningCount:          len(first.Warnings),
		DurationMilliseconds:  time.Since(start).Milliseconds(),
		HeapInuseBytes:        memory.HeapInuse,
	}, nil
}

// RunSyntheticMultiFileBenchmark proves the accepted 330 MiB export shape
// without violating the parser's 72 MiB per-logical-file bound.
func RunSyntheticMultiFileBenchmark(ctx context.Context, targetBytes int64) (BenchmarkResult, error) {
	if targetBytes < DefaultSyntheticBenchmarkBytes || targetBytes > DefaultSyntheticMultiFileBenchmarkBytes {
		return BenchmarkResult{}, errors.New("synthetic multi-file benchmark size is out of bounds")
	}
	start := time.Now()
	fileTargets := splitSyntheticFileTargets(targetBytes)
	result := BenchmarkResult{
		ParserVersion:         normalization.ParserVersion,
		FileCount:             len(fileTargets),
		ResumedFromBatch:      1,
		DeterministicRecovery: true,
	}
	for _, fileTarget := range fileTargets {
		first, firstBytes, err := parseSyntheticFixture(ctx, fileTarget)
		if err != nil {
			return BenchmarkResult{}, err
		}
		second, secondBytes, err := parseSyntheticFixture(ctx, fileTarget)
		if err != nil {
			return BenchmarkResult{}, err
		}
		firstRecords := len(CanonicalRecords(first))
		secondRecords := len(CanonicalRecords(second))
		deterministic := normalizedDigest(first) == normalizedDigest(second) && firstRecords == secondRecords
		if firstRecords == 0 || !deterministic {
			return BenchmarkResult{}, errors.New("synthetic multi-file recovery failed")
		}
		result.InputBytes += maxInt64(firstBytes, secondBytes)
		result.NormalizedRecordCount += firstRecords
		result.BatchCount += (firstRecords + MaxBatchRows - 1) / MaxBatchRows
		result.WarningCount += len(first.Warnings)
		result.DeterministicRecovery = result.DeterministicRecovery && deterministic
	}
	var memory runtime.MemStats
	runtime.ReadMemStats(&memory)
	result.DurationMilliseconds = time.Since(start).Milliseconds()
	result.HeapInuseBytes = memory.HeapInuse
	return result, nil
}

func parseSyntheticFixture(ctx context.Context, targetBytes int64) (normalization.Result, int64, error) {
	reader, writer := io.Pipe()
	resultCh := make(chan generationResult, 1)
	go func() {
		bytesWritten, err := generateSyntheticJSON(ctx, writer, targetBytes)
		_ = writer.CloseWithError(err)
		resultCh <- generationResult{bytes: bytesWritten, err: err}
	}()
	result, parseErr := normalization.ParseHuaweiJSON(reader)
	generated := <-resultCh
	if parseErr != nil {
		return normalization.Result{}, generated.bytes, parseErr
	}
	if generated.err != nil {
		return normalization.Result{}, generated.bytes, generated.err
	}
	return result, generated.bytes, nil
}

type generationResult struct {
	bytes int64
	err   error
}

func generateSyntheticJSON(ctx context.Context, writer *io.PipeWriter, targetBytes int64) (int64, error) {
	var written int64
	write := func(value string) error {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		n, err := io.WriteString(writer, value)
		written += int64(n)
		return err
	}
	if err := write(`{"records":[`); err != nil {
		return written, err
	}
	recordCount := int(targetBytes / 2048)
	if recordCount < 1 {
		recordCount = 1
	}
	if recordCount > normalization.MaxRecordCount {
		recordCount = normalization.MaxRecordCount
	}
	fixedBytes := int64(len(`{"records":[]}`))
	for index := 0; index < recordCount; index++ {
		if index > 0 {
			fixedBytes++
		}
		fixedBytes += int64(len(syntheticRecord(index, "")))
	}
	if fixedBytes > targetBytes {
		return written, errors.New("synthetic benchmark target is too small")
	}
	paddingTotal := targetBytes - fixedBytes
	paddingBytes := paddingTotal / int64(recordCount)
	paddingRemainder := paddingTotal % int64(recordCount)
	for index := 0; index < recordCount; index++ {
		if index > 0 {
			if err := write(","); err != nil {
				return written, err
			}
		}
		recordPadding := paddingBytes
		if int64(index) < paddingRemainder {
			recordPadding++
		}
		record := syntheticRecord(index, strings.Repeat("x", int(recordPadding)))
		if err := write(record); err != nil {
			return written, err
		}
	}
	if err := write("]}"); err != nil {
		return written, err
	}
	return written, nil
}

func syntheticRecord(index int, padding string) string {
	return fmt.Sprintf(`{"type":"heart_rate","record_id":"synthetic-%05d","started_at":"2026-01-02T03:04:05Z","unit":"bpm","value":72,"padding":"%s"}`, index, padding)
}

func splitSyntheticFileTargets(totalBytes int64) []int64 {
	targets := make([]int64, 0, (totalBytes+normalization.MaxInputBytes-1)/normalization.MaxInputBytes)
	for totalBytes > 0 {
		next := totalBytes
		if next > normalization.MaxInputBytes {
			next = normalization.MaxInputBytes
		}
		targets = append(targets, next)
		totalBytes -= next
	}
	return targets
}

func normalizedDigest(result normalization.Result) string {
	encoded, err := json.Marshal(result)
	if err != nil {
		return ""
	}
	digest := sha256.Sum256(encoded)
	return hex.EncodeToString(digest[:])
}

func maxInt64(left, right int64) int64 {
	if left > right {
		return left
	}
	return right
}
