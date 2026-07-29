package worker

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"hash"
	"io"
	"sort"

	"github.com/phukaokub/Health_Tracking/services/api/internal/normalization"
)

// SourcePart is immutable metadata returned by the lease-bound source RPC.
// Object paths are deliberately kept inside the worker adapter.
type SourcePart struct {
	Index  int
	Bytes  int64
	SHA256 string
	Path   string
}

type PartOpener interface {
	OpenPart(context.Context, string) (io.ReadCloser, error)
}

// ParsePrivateParts joins immutable private Storage parts as a bounded stream.
// Every part's length and digest are verified while it is read; no raw source
// is buffered, persisted, or returned on error.
func ParsePrivateParts(ctx context.Context, opener PartOpener, parts []SourcePart) (normalization.Result, error) {
	if opener == nil || len(parts) == 0 {
		return normalization.Result{}, errors.New("source_part_invalid")
	}
	sort.Slice(parts, func(i, j int) bool { return parts[i].Index < parts[j].Index })
	for index, part := range parts {
		if part.Index != index || part.Bytes <= 0 || len(part.SHA256) != 64 || part.Path == "" {
			return normalization.Result{}, errors.New("source_part_invalid")
		}
	}
	reader := &partStream{ctx: ctx, opener: opener, parts: parts}
	result, err := normalization.ParseHuaweiJSON(reader)
	closeErr := reader.Close()
	if err != nil {
		return normalization.Result{}, err
	}
	if closeErr != nil {
		return normalization.Result{}, closeErr
	}
	return result, nil
}

type partStream struct {
	ctx      context.Context
	opener   PartOpener
	parts    []SourcePart
	next     int
	current  io.ReadCloser
	bytes    int64
	hasher   hash.Hash
	finalErr error
}

func (stream *partStream) Read(buffer []byte) (int, error) {
	for {
		if stream.finalErr != nil {
			return 0, stream.finalErr
		}
		if stream.current == nil {
			if stream.next == len(stream.parts) {
				return 0, io.EOF
			}
			part := stream.parts[stream.next]
			body, err := stream.opener.OpenPart(stream.ctx, part.Path)
			if err != nil {
				return 0, errors.New("source_part_unavailable")
			}
			stream.current = body
			stream.bytes = 0
			stream.hasher = sha256.New()
		}
		n, err := stream.current.Read(buffer)
		if n > 0 {
			stream.bytes += int64(n)
			_, _ = stream.hasher.Write(buffer[:n])
		}
		if err == io.EOF {
			part := stream.parts[stream.next]
			_ = stream.current.Close()
			stream.current = nil
			stream.next++
			if stream.bytes != part.Bytes || hex.EncodeToString(stream.hasher.Sum(nil)) != part.SHA256 {
				stream.finalErr = errors.New("source_part_invalid")
				if n > 0 {
					return n, nil
				}
				continue
			}
			if n > 0 {
				return n, nil
			}
			continue
		}
		return n, err
	}
}
func (stream *partStream) Close() error {
	if _, err := io.Copy(io.Discard, stream); err != nil {
		return err
	}
	if stream.current != nil {
		return stream.current.Close()
	}
	return nil
}

// CanonicalRecords flattens only the approved normalized values. Sensitive raw
// families cannot be represented by this contract (no ECG/RRI, GPS or routes).
func CanonicalRecords(result normalization.Result) []map[string]any {
	records := make([]map[string]any, 0, len(result.Samples)+len(result.SleepSessions)+len(result.Activities)+len(result.Workouts))
	for _, value := range result.Samples {
		records = append(records, map[string]any{"kind": "sample", "source_family": value.SourceFamily, "source_type": value.SourceType, "source_record_hash": value.SourceRecordHash, "started_at": value.StartedAt.Format("2006-01-02T15:04:05Z07:00"), "ended_at": value.EndedAt.Format("2006-01-02T15:04:05Z07:00"), "unit": value.Unit, "source_unit": value.SourceUnit, "value": value.Value, "dedupe_key": value.DedupeKey, "parser_version": value.ParserVersion})
	}
	for _, value := range result.SleepSessions {
		records = append(records, map[string]any{"kind": "sleep_session", "source_record_hash": value.SourceRecordHash, "started_at": value.StartedAt.Format("2006-01-02T15:04:05Z07:00"), "ended_at": value.EndedAt.Format("2006-01-02T15:04:05Z07:00"), "duration_seconds": value.DurationSeconds, "dedupe_key": value.DedupeKey, "parser_version": value.ParserVersion})
		for _, stage := range value.Stages {
			records = append(records, map[string]any{"kind": "sleep_stage", "parent_dedupe_key": value.DedupeKey, "stage_code": stage.StageCode, "started_at": stage.StartedAt.Format("2006-01-02T15:04:05Z07:00"), "ended_at": stage.EndedAt.Format("2006-01-02T15:04:05Z07:00"), "dedupe_key": stage.DedupeKey})
		}
	}
	for _, value := range result.Activities {
		records = append(records, map[string]any{"kind": "activity", "source_record_hash": value.SourceRecordHash, "activity_type": value.ActivityType, "started_at": value.StartedAt.Format("2006-01-02T15:04:05Z07:00"), "ended_at": value.EndedAt.Format("2006-01-02T15:04:05Z07:00"), "duration_seconds": value.DurationSeconds, "dedupe_key": value.DedupeKey, "parser_version": value.ParserVersion})
	}
	for _, value := range result.Workouts {
		records = append(records, map[string]any{"kind": "workout", "source_record_hash": value.SourceRecordHash, "workout_type": value.WorkoutType, "started_at": value.StartedAt.Format("2006-01-02T15:04:05Z07:00"), "ended_at": value.EndedAt.Format("2006-01-02T15:04:05Z07:00"), "duration_seconds": value.DurationSeconds, "distance_metres": value.DistanceMetres, "energy_kilocalories": value.EnergyKilocalories, "dedupe_key": value.DedupeKey, "parser_version": value.ParserVersion})
	}
	return records
}

func CanonicalBatches(result normalization.Result) [][]map[string]any {
	records := CanonicalRecords(result)
	if len(records) == 0 {
		return nil
	}
	batches := make([][]map[string]any, 0, (len(records)+MaxBatchRows-1)/MaxBatchRows)
	for len(records) > 0 {
		end := MaxBatchRows
		if end > len(records) {
			end = len(records)
		}
		batches = append(batches, records[:end])
		records = records[end:]
	}
	return batches
}
